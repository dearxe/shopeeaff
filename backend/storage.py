import hashlib
import json
import secrets
import sqlite3
import time
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

from .errors import APIError
from .urls import validate_url, product_identity


def timestamp():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def token_hash(token):
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def validate_uuid(value, label):
    try:
        if not isinstance(value, str) or str(uuid.UUID(value)) != value.lower():
            raise ValueError()
    except (ValueError, AttributeError):
        raise APIError(400, "INVALID_REQUEST", f"{label} ต้องเป็น UUID") from None
    return value.lower()


def normalize_request(body):
    if not isinstance(body, dict) or set(body) - {"clientRequestId", "originalUrl", "tracking"}:
        raise APIError(400, "INVALID_REQUEST", "ฟิลด์คำขอไม่ถูกต้อง")
    result = {"clientRequestId": validate_uuid(body.get("clientRequestId"), "clientRequestId"),
              "originalUrl": validate_url(body.get("originalUrl"))}
    tracking = body.get("tracking")
    if tracking is not None:
        if not isinstance(tracking, dict) or set(tracking) != {"channel", "subIdPrefixes"}:
            raise APIError(400, "INVALID_TRACKING", "ข้อมูล tracking ไม่ถูกต้อง")
        channel = tracking["channel"]
        prefixes = tracking["subIdPrefixes"]
        if (channel not in ("tiktok", "facebook", "line", "instagram") or not isinstance(prefixes, list)
                or not 1 <= len(prefixes) <= 3 or any(p not in ("ios", "affiliate", "shop") for p in prefixes)):
            raise APIError(400, "INVALID_TRACKING", "ช่องทางหรือ prefix ไม่รองรับ")
        result["tracking"] = {"channel": channel, "subIdPrefixes": prefixes}
    return result


class Store:
    def __init__(self, path, max_pending=100):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.max_pending = max_pending
        with self.connection() as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.executescript("""
                CREATE TABLE IF NOT EXISTS clients (
                    id TEXT PRIMARY KEY, name TEXT NOT NULL, token_hash TEXT UNIQUE NOT NULL,
                    revoked INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS jobs (
                    id TEXT PRIMARY KEY, principal TEXT NOT NULL REFERENCES clients(id),
                    client_request_id TEXT NOT NULL, request_json TEXT NOT NULL,
                    status TEXT NOT NULL, original_url TEXT NOT NULL, resolved_url TEXT,
                    affiliate_url TEXT, error_json TEXT, created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL, UNIQUE(principal, client_request_id));
                CREATE TABLE IF NOT EXISTS idempotency (
                    principal TEXT NOT NULL REFERENCES clients(id), key TEXT NOT NULL,
                    request_json TEXT NOT NULL, job_id TEXT NOT NULL REFERENCES jobs(id),
                    PRIMARY KEY(principal,key));
                CREATE TABLE IF NOT EXISTS audit (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, job_id TEXT NOT NULL REFERENCES jobs(id),
                    action TEXT NOT NULL, details_json TEXT NOT NULL, created_at TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY,value TEXT NOT NULL);
                CREATE INDEX IF NOT EXISTS jobs_status_created ON jobs(status,created_at);
            """)

    @contextmanager
    def connection(self, immediate=False):
        db = sqlite3.connect(self.path, timeout=10)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys=ON")
        db.execute("PRAGMA busy_timeout=10000")
        try:
            if immediate:
                db.execute("BEGIN IMMEDIATE")
            yield db
            db.commit()
        except BaseException:
            db.rollback()
            raise
        finally:
            db.close()

    def provision(self, name):
        token = secrets.token_urlsafe(32)
        principal = "device_" + uuid.uuid4().hex
        with self.connection() as db:
            db.execute("INSERT INTO clients(id,name,token_hash,created_at) VALUES(?,?,?,?)", (principal, name, token_hash(token), timestamp()))
        return principal, token

    def authenticate(self, token):
        if not token or len(token) > 256:
            raise APIError(401, "UNAUTHORIZED", "กรุณาตรวจรหัสเชื่อมต่อ")
        with self.connection() as db:
            row = db.execute("SELECT id FROM clients WHERE token_hash=? AND revoked=0", (token_hash(token),)).fetchone()
        if not row:
            raise APIError(401, "UNAUTHORIZED", "กรุณาตรวจรหัสเชื่อมต่อ")
        return row["id"]

    def revoke(self, principal):
        with self.connection() as db:
            return db.execute("UPDATE clients SET revoked=1 WHERE id=?", (principal,)).rowcount

    def create(self, principal, key, body):
        key = validate_uuid(key, "Idempotency-Key")
        request = normalize_request(body)
        canonical = json.dumps(request, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        with self.connection(immediate=True) as db:
            old = db.execute("SELECT * FROM idempotency WHERE principal=? AND key=?", (principal, key)).fetchone()
            if old:
                if old["request_json"] != canonical:
                    raise APIError(409, "IDEMPOTENCY_CONFLICT", "key เดิมถูกใช้กับข้อมูลต่างกัน")
                return self.encode(db.execute("SELECT * FROM jobs WHERE id=?", (old["job_id"],)).fetchone())
            old_job = db.execute("SELECT * FROM jobs WHERE principal=? AND client_request_id=?", (principal, request["clientRequestId"])).fetchone()
            if old_job and old_job["request_json"] != canonical:
                raise APIError(409, "IDEMPOTENCY_CONFLICT", "clientRequestId เดิมถูกใช้กับข้อมูลต่างกัน")
            if old_job:
                job_id = old_job["id"]
            else:
                pending = db.execute("SELECT COUNT(*) FROM jobs WHERE status NOT IN ('completed','failed')").fetchone()[0]
                if pending >= self.max_pending:
                    raise APIError(429, "QUEUE_FULL", "คิวเต็ม กรุณาลองด้วย key เดิมภายหลัง", True, 30)
                job_id = "job_" + uuid.uuid4().hex
                now = timestamp()
                db.execute("INSERT INTO jobs(id,principal,client_request_id,request_json,status,original_url,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)",
                           (job_id, principal, request["clientRequestId"], canonical, "queued", request["originalUrl"], now, now))
            db.execute("INSERT INTO idempotency(principal,key,request_json,job_id) VALUES(?,?,?,?)", (principal, key, canonical, job_id))
            return self.encode(db.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone())

    def get(self, principal, job_id):
        with self.connection() as db:
            row = db.execute("SELECT * FROM jobs WHERE id=? AND principal=?", (job_id, principal)).fetchone()
        if not row:
            raise APIError(404, "NOT_FOUND", "ไม่พบงาน")
        return self.encode(row)

    @staticmethod
    def encode(row):
        result = {"jobId": row["id"], "status": row["status"], "originalUrl": row["original_url"],
                  "createdAt": row["created_at"], "updatedAt": row["updated_at"]}
        if row["status"] == "completed":
            if not row["affiliate_url"]:
                raise APIError(503, "INVALID_STORED_RESULT", "ข้อมูลผลลัพธ์ไม่ครบ", False)
            result["affiliateUrl"] = validate_url(row["affiliate_url"])
        if row["error_json"]:
            result["error"] = json.loads(row["error_json"])
        if row["status"] not in ("completed", "failed"):
            result["retryAfterSeconds"] = 30 if row["status"] == "waiting_for_operator" else 2
        return result

    def operator_jobs(self, limit=100):
        with self.connection() as db:
            rows = db.execute("SELECT * FROM jobs ORDER BY CASE WHEN status IN ('completed','failed') THEN 1 ELSE 0 END, created_at DESC LIMIT ?", (limit,)).fetchall()
        results = []
        for row in rows:
            result = self.encode(row)
            result.update({"tracking": json.loads(row["request_json"]).get("tracking"), "resolvedUrl": row["resolved_url"], "principal": row["principal"]})
            results.append(result)
        return results

    def raw_job(self, job_id):
        with self.connection() as db:
            row = db.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
        if not row:
            raise APIError(404, "NOT_FOUND", "ไม่พบงาน")
        return dict(row)

    def claim(self):
        with self.connection(immediate=True) as db:
            row = db.execute("SELECT * FROM jobs WHERE status='queued' ORDER BY created_at LIMIT 1").fetchone()
            if not row:
                return None
            db.execute("UPDATE jobs SET status='processing',updated_at=? WHERE id=? AND status='queued'", (timestamp(), row["id"]))
            return dict(row)

    def finish(self, job_id, status, *, error=None, resolved=None, affiliate=None, audit=None):
        if status not in ("waiting_for_operator", "completed", "failed"):
            raise ValueError("Invalid state transition")
        if status == "completed":
            validate_url(affiliate)
            if error is not None or not product_identity(resolved):
                raise APIError(400, "INVALID_RESULT", "ต้องมีลิงก์สินค้าและ Affiliate ที่ตรวจแล้ว")
        if status == "failed" and not error:
            raise ValueError("Failed jobs require an error")
        with self.connection(immediate=True) as db:
            old = db.execute("SELECT status FROM jobs WHERE id=?", (job_id,)).fetchone()
            if not old:
                raise APIError(404, "NOT_FOUND", "ไม่พบงาน")
            if old["status"] in ("completed", "failed"):
                raise APIError(409, "TERMINAL_JOB", "งานจบแล้ว ไม่เปลี่ยนผลย้อนหลัง")
            if old["status"] != "processing" and status == "waiting_for_operator":
                raise APIError(409, "STATE_CONFLICT", "งานไม่ได้อยู่ระหว่างตรวจ")
            db.execute("UPDATE jobs SET status=?,error_json=?,resolved_url=COALESCE(?,resolved_url),affiliate_url=?,updated_at=? WHERE id=?",
                       (status, json.dumps(error, ensure_ascii=False) if error else None, resolved, affiliate if status == "completed" else None, timestamp(), job_id))
            db.execute("INSERT INTO audit(job_id,action,details_json,created_at) VALUES(?,?,?,?)",
                       (job_id, status, json.dumps(audit or {}, ensure_ascii=False), timestamp()))

    def recover(self):
        # Only called once before starting the single local worker.
        with self.connection() as db:
            db.execute("UPDATE jobs SET status='queued',updated_at=? WHERE status='processing'", (timestamp(),))

    def heartbeat(self):
        with self.connection() as db:
            db.execute("INSERT INTO metadata(key,value) VALUES('worker_heartbeat',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (str(time.time()),))

    def worker_status(self):
        with self.connection() as db:
            row = db.execute("SELECT value FROM metadata WHERE key='worker_heartbeat'").fetchone()
        return "needs_attention" if row and time.time() - float(row[0]) < 30 else "offline"

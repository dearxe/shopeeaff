import hmac
import ipaddress
import json
import secrets
import sqlite3
import threading
import time
from collections import OrderedDict, deque
from pathlib import Path
from urllib.parse import urlsplit

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, FileResponse
from starlette.exceptions import HTTPException
from starlette.concurrency import run_in_threadpool

from .errors import APIError
from .urls import validate_url, product_identity, ResolverUnavailable

STATIC = Path(__file__).parent / "static"


class Limiter:
    def __init__(self, maximum_keys=4096):
        self.keys = OrderedDict()
        self.maximum_keys = maximum_keys
        self.lock = threading.Lock()

    def check(self, key, limit, window=60):
        now = time.monotonic()
        with self.lock:
            events = self.keys.setdefault(key, deque())
            self.keys.move_to_end(key)
            while events and events[0] <= now - window:
                events.popleft()
            if len(events) >= limit:
                raise APIError(429, "RATE_LIMITED", "ส่งคำขอบ่อยเกินไป กรุณารอ", True, max(1, int(window - (now - events[0])) + 1))
            events.append(now)
            while len(self.keys) > self.maximum_keys:
                self.keys.popitem(last=False)


async def json_body(request):
    if request.headers.get("content-type", "").split(";", 1)[0].lower() != "application/json":
        raise APIError(415, "INVALID_CONTENT_TYPE", "ต้องส่ง application/json")
    size = 0
    chunks = []
    async for chunk in request.stream():
        size += len(chunk)
        if size > 16384:
            raise APIError(413, "BODY_TOO_LARGE", "คำขอใหญ่เกินไป")
        chunks.append(chunk)
    try:
        body = json.loads(b"".join(chunks))
    except (ValueError, UnicodeError):
        raise APIError(400, "INVALID_JSON", "JSON ไม่ถูกต้อง") from None
    if not isinstance(body, dict):
        raise APIError(400, "INVALID_REQUEST", "ต้องส่ง JSON object")
    return body


def error_response(error):
    headers = {"Retry-After": str(error.retry_after)} if error.retry_after is not None else None
    return JSONResponse({"error": error.detail()}, status_code=error.status, headers=headers)


def app_base(title):
    app = FastAPI(title=title, docs_url=None, redoc_url=None, openapi_url=None, redirect_slashes=False)

    @app.exception_handler(APIError)
    async def api_error(request, error):
        return error_response(error)

    @app.exception_handler(RequestValidationError)
    async def request_error(request, error):
        return error_response(APIError(400, "INVALID_REQUEST", "รูปแบบคำขอไม่ถูกต้อง"))

    @app.exception_handler(HTTPException)
    async def http_error(request, error):
        return error_response(APIError(error.status_code, "NOT_FOUND" if error.status_code == 404 else "HTTP_ERROR", "ไม่มี endpoint หรือ method นี้"))

    @app.exception_handler(sqlite3.OperationalError)
    async def database_error(request, error):
        return error_response(APIError(503, "STORAGE_UNAVAILABLE", "ฐานข้อมูลยังไม่พร้อม กรุณาลองด้วย key เดิม", True, 5))

    @app.exception_handler(Exception)
    async def internal_error(request, error):
        return error_response(APIError(500, "INTERNAL_ERROR", "ระบบยังไม่สามารถตอบคำขอได้ กรุณาลองด้วย key เดิม", True, 5))

    @app.middleware("http")
    async def security_headers(request, call_next):
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Content-Security-Policy"] = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; frame-ancestors 'none'; form-action 'self'; base-uri 'none'"
        return response

    return app


def create_api(store, limiter=None):
    app = app_base("Affiliate Link Helper API")
    limiter = limiter or Limiter()

    def principal(request, submit=False):
        address = request.client.host if request.client else "unknown"
        limiter.check(("requests", address), 240)
        authorization = request.headers.get("authorization", "")
        if not authorization.startswith("Bearer "):
            raise APIError(401, "UNAUTHORIZED", "กรุณาส่งรหัสเชื่อมต่อ")
        identity = store.authenticate(authorization[7:])
        limiter.check(("principal", identity), 120)
        if submit:
            limiter.check(("submit", identity), 20)
        return identity

    @app.post("/v1/link-jobs")
    async def create_job(request: Request):
        identity = await run_in_threadpool(principal, request, True)
        key = request.headers.get("idempotency-key")
        body = await json_body(request)
        job = await run_in_threadpool(store.create, identity, key, body)
        status = 200 if job["status"] in ("completed", "failed") else 202
        headers = {"Retry-After": str(job["retryAfterSeconds"])} if "retryAfterSeconds" in job else None
        return JSONResponse(job, status_code=status, headers=headers)

    @app.get("/v1/link-jobs/{job_id}")
    def get_job(job_id: str, request: Request):
        identity = principal(request)
        job = store.get(identity, job_id)
        headers = {"Retry-After": str(job["retryAfterSeconds"])} if "retryAfterSeconds" in job else None
        return JSONResponse(job, headers=headers)

    @app.get("/v1/health")
    def health(request: Request):
        principal(request)
        return {"apiStatus": "ok", "workerStatus": store.worker_status()}

    return app


class Sessions:
    def __init__(self):
        self.sessions = {}
        self.lock = threading.Lock()

    def create(self):
        token = secrets.token_urlsafe(32)
        csrf = secrets.token_urlsafe(32)
        now = time.monotonic()
        with self.lock:
            self.sessions = {k: v for k, v in self.sessions.items() if v[1] > now}
            if len(self.sessions) >= 64:
                raise APIError(429, "TOO_MANY_SESSIONS", "มี session ผู้ดูแลมากเกินไป", True, 60)
            self.sessions[token] = (csrf, now + 8 * 3600)
        return token, csrf

    def check(self, request, write=False):
        token = request.cookies.get("operator_session", "")
        with self.lock:
            record = self.sessions.get(token)
            if not record or record[1] < time.monotonic():
                self.sessions.pop(token, None)
                raise APIError(401, "UNAUTHORIZED", "กรุณาเข้าสู่ระบบผู้ดูแล")
            csrf = record[0]
        if write and not hmac.compare_digest(request.headers.get("x-csrf-token", "").encode(), csrf.encode()):
            raise APIError(403, "CSRF_REJECTED", "กรุณาเปิดหน้าผู้ดูแลใหม่")
        return csrf

    def remove(self, request):
        with self.lock:
            self.sessions.pop(request.cookies.get("operator_session", ""), None)


def create_admin(store, admin_code, resolver, owner_id="15349870042", port=8081, test_client_code=None):
    app = app_base("Affiliate Link Helper Local Operator")
    sessions = Sessions()
    limiter = Limiter()
    origins = {f"http://127.0.0.1:{port}", f"http://localhost:{port}"}

    @app.middleware("http")
    async def local_only(request, call_next):
        try:
            address = request.client.host if request.client else ""
            if not ipaddress.ip_address(address).is_loopback:
                raise ValueError()
            host = urlsplit("http://" + request.headers.get("host", "")).hostname
            if host not in ("127.0.0.1", "localhost"):
                raise ValueError()
            origin = request.headers.get("origin")
            if origin and origin not in origins:
                raise ValueError()
            if request.method not in ("GET", "HEAD") and origin not in origins:
                raise ValueError()
            if request.headers.get("sec-fetch-site") == "cross-site":
                raise ValueError()
        except ValueError:
            return error_response(APIError(403, "LOCAL_OPERATOR_ONLY", "เปิดหน้าผู้ดูแลจาก PC เครื่องนี้เท่านั้น"))
        return await call_next(request)

    @app.get("/")
    def index():
        return FileResponse(STATIC / "index.html")

    @app.get("/operator.js")
    def javascript():
        return FileResponse(STATIC / "operator.js", media_type="application/javascript")

    @app.get("/operator.css")
    def stylesheet():
        return FileResponse(STATIC / "operator.css", media_type="text/css")

    @app.post("/operator/login")
    async def login(request: Request):
        limiter.check(("login", request.client.host), 5)
        body = await json_body(request)
        code = body.get("code")
        if not isinstance(code, str) or len(code) > 256 or not hmac.compare_digest(code.encode(), admin_code.encode()):
            raise APIError(401, "UNAUTHORIZED", "รหัสผู้ดูแลไม่ถูกต้อง")
        token, csrf = sessions.create()
        response = JSONResponse({"csrfToken": csrf})
        # HTTP is allowed only on this loopback operator port; never publish this port.
        response.set_cookie("operator_session", token, httponly=True, samesite="strict", max_age=8 * 3600, path="/")
        return response

    @app.get("/operator/session")
    def session(request: Request):
        return {"csrfToken": sessions.check(request), "ownerAffiliateId": owner_id}

    @app.post("/operator/logout")
    def logout(request: Request):
        sessions.check(request, True)
        sessions.remove(request)
        response = JSONResponse({"ok": True})
        response.delete_cookie("operator_session", path="/")
        return response

    @app.get("/operator/jobs")
    def jobs(request: Request):
        sessions.check(request)
        return {"jobs": store.operator_jobs(), "workerStatus": store.worker_status(), "mode": "manual_operator", "ownerAffiliateId": owner_id}

    @app.post("/operator/test-jobs")
    async def local_test_job(request: Request):
        sessions.check(request, True)
        limiter.check("operator-create", 20)
        if not test_client_code:
            raise APIError(503, "TEST_CLIENT_UNAVAILABLE", "ยังไม่มีรหัสอุปกรณ์สำหรับทดสอบ", False)
        identity = await run_in_threadpool(store.authenticate, test_client_code)
        body = await json_body(request)
        job = await run_in_threadpool(store.create, identity, request.headers.get("idempotency-key"), body)
        return JSONResponse(job, status_code=200 if job["status"] in ("completed", "failed") else 202)

    @app.post("/operator/jobs/{job_id}/complete")
    async def complete(job_id: str, request: Request):
        sessions.check(request, True)
        limiter.check("operator-writes", 30)
        body = await json_body(request)
        if body.get("ownershipConfirmed") is not True or body.get("destinationVerified") is not True:
            raise APIError(400, "CONFIRMATION_REQUIRED", "ต้องตรวจสินค้าและยืนยันสร้างจากบัญชีเจ้าของจริง")
        affiliate = validate_url(body.get("affiliateUrl"))
        product = validate_url(body.get("verifiedProductUrl"))
        identity = product_identity(product)
        if not identity:
            raise APIError(400, "NOT_PRODUCT_URL", "กรุณาใส่ URL สินค้าฉบับเต็มที่ตรวจในเบราว์เซอร์แล้ว")
        job = await run_in_threadpool(store.raw_job, job_id)
        if job["status"] != "waiting_for_operator":
            raise APIError(409, "STATE_CONFLICT", "รอให้งานเข้าสถานะรอผู้ดูแลก่อน")
        source_identity = product_identity(job["resolved_url"]) if job["resolved_url"] else product_identity(job["original_url"])
        if source_identity and source_identity != identity:
            raise APIError(400, "PRODUCT_MISMATCH", "สินค้าที่ตรวจไม่ตรงกับคำขอ")
        verification = "network_verified"
        try:
            final = await run_in_threadpool(resolver.resolve, affiliate)
            if product_identity(final) != identity:
                raise APIError(400, "PRODUCT_MISMATCH", "Affiliate URL ชี้ไปสินค้าคนละรายการ")
        except ResolverUnavailable:
            # Explicit trusted-operator attestation, never a simulated success.
            verification = "operator_attested_storefront_blocked"
        await run_in_threadpool(store.finish, job_id, "completed", resolved=product, affiliate=affiliate,
                               audit={"verification": verification, "ownerAffiliateId": owner_id, "ownershipConfirmed": True, "destinationVerified": True})
        return {"ok": True, "verification": verification}

    @app.post("/operator/jobs/{job_id}/fail")
    async def fail(job_id: str, request: Request):
        sessions.check(request, True)
        body = await json_body(request)
        message = body.get("message", "ผู้ดูแลไม่สามารถสร้างลิงก์ให้คำขอนี้ได้")
        if not isinstance(message, str) or not 1 <= len(message) <= 500:
            raise APIError(400, "INVALID_REQUEST", "เหตุผลต้องยาว 1–500 ตัวอักษร")
        job = await run_in_threadpool(store.raw_job, job_id)
        if job["status"] != "waiting_for_operator":
            raise APIError(409, "STATE_CONFLICT", "ต้องเป็นงานรอผู้ดูแล")
        await run_in_threadpool(store.finish, job_id, "failed", error={"code": "OPERATOR_FAILED", "message": message, "retryable": False}, audit={"actor": "local_operator"})
        return {"ok": True}

    return app

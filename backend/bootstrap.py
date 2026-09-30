import json
import os
import secrets
from pathlib import Path

from .storage import Store, token_hash


def initialize(data_directory):
    directory = Path(data_directory)
    directory.mkdir(parents=True, exist_ok=True)
    store = Store(directory / "jobs.sqlite3")
    config_file = directory / "connection-codes.json"
    if config_file.exists():
        config = json.loads(config_file.read_text(encoding="utf-8"))
        if not config.get("adminAccessCode") or not config.get("clientConnectionCode"):
            raise RuntimeError("Invalid private config; refusing to rotate credentials silently.")
        with store.connection() as db:
            identity = db.execute("SELECT id FROM clients WHERE token_hash=?", (token_hash(config["clientConnectionCode"]),)).fetchone()
        if not identity or identity["id"] != config.get("clientId"):
            raise RuntimeError("Private config does not match the database identity.")
    else:
        with store.connection() as db:
            if db.execute("SELECT COUNT(*) FROM clients").fetchone()[0]:
                raise RuntimeError("Private connection-codes.json is missing; restore it instead of silently replacing identity.")
        identity, client_code = store.provision("Owner iPhone")
        config = {"adminAccessCode": secrets.token_urlsafe(32), "clientConnectionCode": client_code,
                  "clientId": identity, "ownerAffiliateId": "15349870042", "mode": "manual_operator"}
        # Never print, log or commit this file. The launch script restricts Windows ACLs.
        descriptor = os.open(config_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(config, handle, indent=2)
    return store, config

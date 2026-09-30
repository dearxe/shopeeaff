"""Local-only credential provisioning and revocation; tokens are saved, never printed."""
import argparse
import json
import os
from pathlib import Path

from .bootstrap import initialize


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", default=str(Path(__file__).resolve().parents[1] / ".local/backend"))
    commands = parser.add_subparsers(dest="command", required=True)
    provision = commands.add_parser("provision-client")
    provision.add_argument("--name", required=True)
    revoke = commands.add_parser("revoke-client")
    revoke.add_argument("--client-id", required=True)
    commands.add_parser("list-clients")
    args = parser.parse_args()
    store, _ = initialize(args.data_dir)
    if args.command == "provision-client":
        if not 1 <= len(args.name) <= 100:
            parser.error("Use a name of 1–100 characters")
        identity, code = store.provision(args.name)
        file = Path(args.data_dir) / f"{identity}.json"
        descriptor = os.open(file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump({"clientId": identity, "name": args.name, "clientConnectionCode": code}, handle, ensure_ascii=False, indent=2)
        print(f"Created client {identity}. Connection code saved privately to {file}; not printed.")
    elif args.command == "revoke-client":
        if not store.revoke(args.client_id):
            parser.error("Client not found")
        print("Client access revoked. Existing jobs and idempotency mappings were retained.")
    else:
        with store.connection() as db:
            rows = db.execute("SELECT id,name,revoked,created_at FROM clients ORDER BY created_at").fetchall()
        print(json.dumps([dict(row) for row in rows], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

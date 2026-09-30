import argparse
import logging
import signal
import socket
import threading
import time
from pathlib import Path

import uvicorn

from .apps import create_api, create_admin
from .bootstrap import initialize
from .urls import SafeResolver
from .worker import OperatorWorker


def main():
    parser = argparse.ArgumentParser(description="Local Affiliate Link Helper API and operator dashboard")
    parser.add_argument("--data-dir", default=str(Path(__file__).resolve().parents[1] / ".local" / "backend"))
    parser.add_argument("--api-port", type=int, default=8080)
    parser.add_argument("--admin-port", type=int, default=8081)
    args = parser.parse_args()
    if args.api_port == args.admin_port:
        parser.error("Use separate API and local operator ports")
    # Stop before recovering jobs if another instance/server already owns either port.
    for port in (args.api_port, args.admin_port):
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", port))
    store, config = initialize(args.data_dir)
    store.recover()
    resolver = SafeResolver()
    worker = OperatorWorker(store, resolver)
    apps = [(create_api(store), args.api_port),
            (create_admin(store, config["adminAccessCode"], resolver, config["ownerAffiliateId"], args.admin_port, config["clientConnectionCode"]), args.admin_port)]
    servers = [uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=port, proxy_headers=False,
                                            access_log=False, log_level="warning", limit_concurrency=50,
                                            timeout_keep_alive=5, timeout_graceful_shutdown=10)) for app, port in apps]
    threads = [threading.Thread(target=server.run, name=f"http-{port}", daemon=True) for server, (_, port) in zip(servers, apps)]
    stop = threading.Event()
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    worker.start()
    for thread in threads:
        thread.start()
    logging.warning("Local Backend running: API 127.0.0.1:%s; operator 127.0.0.1:%s; mode manual_operator. No public listener.", args.api_port, args.admin_port)
    try:
        while not stop.wait(1):
            if not all(thread.is_alive() for thread in threads):
                raise RuntimeError("A local server stopped unexpectedly")
            if worker.thread.is_alive():
                store.heartbeat()
    finally:
        for server in servers:
            server.should_exit = True
        worker.stop()
        for thread in threads:
            thread.join(timeout=15)


if __name__ == "__main__":
    main()

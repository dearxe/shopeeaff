import asyncio
import socket
import tempfile
import threading
import time
import unittest
import uuid
from pathlib import Path

import httpx
import uvicorn

from backend.apps import create_api
from backend.storage import Store


class DelayedFirstPOST:
    """Fault injection at transport boundary, after the actual transaction commits."""
    def __init__(self, app):
        self.app = app
        self.delayed = False

    async def __call__(self, scope, receive, send):
        async def delay_send(message):
            if scope.get("method") == "POST" and message["type"] == "http.response.start" and not self.delayed:
                self.delayed = True
                await asyncio.sleep(0.5)
            await send(message)
        await self.app(scope, receive, delay_send)


class LiveHTTPTests(unittest.TestCase):
    def test_timeout_after_commit_retry_does_not_enqueue_again(self):
        with tempfile.TemporaryDirectory() as directory:
            store = Store(Path(directory) / "jobs.sqlite3")
            principal, token = store.provision("isolated transport test")
            app = DelayedFirstPOST(create_api(store))
            sock = socket.socket()
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
            server = uvicorn.Server(uvicorn.Config(app, access_log=False, log_level="critical"))
            thread = threading.Thread(target=lambda: server.run(sockets=[sock]), daemon=True)
            thread.start()
            try:
                deadline = time.monotonic() + 5
                while not server.started and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(server.started)
                headers = {"Authorization": "Bearer " + token, "Idempotency-Key": str(uuid.uuid4())}
                body = {"clientRequestId": str(uuid.uuid4()), "originalUrl": "https://shopee.co.th/product/123/456"}
                url = f"http://127.0.0.1:{port}/v1/link-jobs"
                with httpx.Client(timeout=0.15, trust_env=False) as client:
                    with self.assertRaises(httpx.ReadTimeout):
                        client.post(url, json=body, headers=headers)
                self.assertEqual(len(store.operator_jobs()), 1)
                accepted_id = store.operator_jobs()[0]["jobId"]
                with httpx.Client(timeout=3, trust_env=False) as client:
                    response = client.post(url, json=body, headers=headers)
                self.assertEqual(response.status_code, 202)
                self.assertEqual(response.json()["jobId"], accepted_id)
                self.assertEqual(len(store.operator_jobs()), 1)
                reopened = Store(store.path)
                self.assertEqual(reopened.get(principal, accepted_id)["status"], "queued")
            finally:
                server.should_exit = True
                thread.join(timeout=5)
                sock.close()
            self.assertFalse(thread.is_alive())

import logging
import threading

from .errors import APIError
from .urls import ResolverUnavailable


class OperatorWorker:
    def __init__(self, store, resolver):
        self.store = store
        self.resolver = resolver
        self.stop_event = threading.Event()
        self.thread = None

    def step(self):
        self.store.heartbeat()
        job = self.store.claim()
        if not job:
            return False
        try:
            destination = self.resolver.resolve(job["original_url"])
            self.store.finish(job["id"], "waiting_for_operator", resolved=destination,
                              audit={"sourceDestination": "network_verified"})
        except ResolverUnavailable:
            self.store.finish(job["id"], "waiting_for_operator",
                              error={"code": "OPERATOR_VERIFICATION_REQUIRED", "message": "เว็บสินค้าไม่ให้ตรวจอัตโนมัติ ผู้ดูแลต้องตรวจปลายทางในเบราว์เซอร์ก่อนสร้างลิงก์", "retryable": True},
                              audit={"sourceDestination": "operator_verification_required"})
        except APIError as error:
            self.store.finish(job["id"], "failed", error=error.detail(), audit={"sourceDestination": "rejected"})
        return True

    def run(self):
        while not self.stop_event.is_set():
            try:
                active = self.step()
            except Exception:
                # Do not log request URLs, account material or exception payloads.
                logging.error("Worker paused after internal error; unfinished processing is recovered on restart.")
                active = False
            self.stop_event.wait(0.1 if active else 1)

    def start(self):
        self.thread = threading.Thread(target=self.run, name="affiliate-operator-worker", daemon=True)
        self.thread.start()

    def stop(self):
        self.stop_event.set()
        if self.thread:
            self.thread.join(timeout=10)

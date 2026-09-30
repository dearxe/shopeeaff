import concurrent.futures
import json
import socket
import tempfile
import unittest
import uuid
from pathlib import Path

from fastapi.testclient import TestClient

from backend.apps import create_api, create_admin, Limiter
from backend.bootstrap import initialize
from backend.errors import APIError
from backend.storage import Store
from backend.urls import validate_url, product_identity, SafeResolver, ResolverUnavailable
from backend.worker import OperatorWorker

PRODUCT = "https://shopee.co.th/product/123/456?preserve=a%20b"
AFFILIATE = "https://shope.ee/example-only-for-unit-tests"


class ResolverStub:
    def __init__(self, value=PRODUCT, error=None):
        self.value = value
        self.error = error

    def resolve(self, value):
        if self.error:
            raise self.error
        return self.value


class BackendTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.path = Path(self.directory.name) / "jobs.sqlite3"
        self.store = Store(self.path)
        self.identity, self.token = self.store.provision("first device")
        self.other, self.other_token = self.store.provision("other device")
        self.client = TestClient(create_api(self.store), base_url="http://127.0.0.1:8080", client=("127.0.0.1", 9001))
        self.client.headers["Authorization"] = "Bearer " + self.token
        self.body = {"clientRequestId": str(uuid.uuid4()), "originalUrl": PRODUCT,
                     "tracking": {"channel": "line", "subIdPrefixes": ["ios", "affiliate", "shop"]}}
        self.key = str(uuid.uuid4())

    def tearDown(self):
        self.client.close()
        self.directory.cleanup()

    def post(self, body=None, key=None):
        return self.client.post("/v1/link-jobs", json=body or self.body, headers={"Idempotency-Key": key or self.key})

    def operator(self, resolver=None):
        client = TestClient(create_admin(self.store, "unit-admin-code", resolver or ResolverStub()), base_url="http://127.0.0.1:8081", client=("127.0.0.1", 9002))
        client.headers["Origin"] = "http://127.0.0.1:8081"
        response = client.post("/operator/login", json={"code": "unit-admin-code"})
        self.assertEqual(response.status_code, 200)
        client.headers["X-CSRF-Token"] = response.json()["csrfToken"]
        return client

    def create_and_wait(self):
        response = self.post()
        self.assertEqual(response.status_code, 202)
        job = response.json()
        OperatorWorker(self.store, ResolverStub()).step()
        return job["jobId"]

    def test_http_contract_and_preserved_query(self):
        response = self.post()
        self.assertEqual(response.status_code, 202)
        job = response.json()
        self.assertEqual(job["status"], "queued")
        self.assertEqual(job["originalUrl"], PRODUCT)
        self.assertNotIn("affiliateUrl", job)
        self.assertEqual(response.headers["Retry-After"], "2")
        self.assertEqual(self.client.get("/v1/link-jobs/" + job["jobId"]).json(), job)
        self.assertEqual(self.client.get("/v1/health").json(), {"apiStatus": "ok", "workerStatus": "offline"})

    def test_idempotency_and_conflicts(self):
        first = self.post().json()
        self.assertEqual(self.post().json()["jobId"], first["jobId"])
        changed = dict(self.body, originalUrl="https://shope.ee/different")
        self.assertEqual(self.post(changed).status_code, 409)
        changed_tracking = dict(self.body, tracking={"channel": "instagram", "subIdPrefixes": ["ios"]})
        self.assertEqual(self.post(changed_tracking).status_code, 409)
        self.assertEqual(self.post(changed, str(uuid.uuid4())).status_code, 409)
        self.assertEqual(self.post(key=str(uuid.uuid4())).json()["jobId"], first["jobId"])

    def test_concurrent_requests_enqueue_once(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
            results = list(executor.map(lambda _: self.store.create(self.identity, self.key, self.body), range(16)))
        self.assertEqual(len({j["jobId"] for j in results}), 1)
        self.assertEqual(len(self.store.operator_jobs()), 1)

    def test_persistent_restart_and_processing_recovery(self):
        first = self.post().json()
        self.store.claim()
        reopened = Store(self.path)
        reopened.recover()
        self.assertEqual(reopened.get(self.identity, first["jobId"])["status"], "queued")
        self.assertEqual(reopened.create(self.identity, self.key, self.body)["jobId"], first["jobId"])

    def test_principal_isolation_and_revocation(self):
        first = self.post().json()
        self.client.headers["Authorization"] = "Bearer " + self.other_token
        response = self.client.get("/v1/link-jobs/" + first["jobId"])
        self.assertEqual(response.status_code, 404)
        second = self.post().json()
        self.assertNotEqual(second["jobId"], first["jobId"])
        self.store.revoke(self.other)
        self.assertEqual(self.client.get("/v1/health").status_code, 401)
        self.assertNotIn(self.token, self.path.read_bytes().decode("latin1"))

    def test_operator_completion_and_replay(self):
        job_id = self.create_and_wait()
        self.assertEqual(self.client.get("/v1/link-jobs/" + job_id).json()["status"], "waiting_for_operator")
        self.assertEqual(self.client.get("/v1/health").json()["workerStatus"], "needs_attention")
        with self.operator() as operator:
            result = operator.post("/operator/jobs/" + job_id + "/complete", json={"affiliateUrl": AFFILIATE, "verifiedProductUrl": PRODUCT, "ownershipConfirmed": True, "destinationVerified": True})
            self.assertEqual(result.status_code, 200)
            self.assertEqual(result.json()["verification"], "network_verified")
            self.assertEqual(operator.post("/operator/jobs/" + job_id + "/fail", json={"message": "change"}).status_code, 409)
        job = self.client.get("/v1/link-jobs/" + job_id).json()
        self.assertEqual(job["status"], "completed")
        self.assertEqual(job["affiliateUrl"], AFFILIATE)
        self.assertNotIn("error", job)
        self.assertEqual(self.post().status_code, 200)

    def test_offline_requires_operator_never_fabricates_success(self):
        job_id = self.post().json()["jobId"]
        OperatorWorker(self.store, ResolverStub(error=ResolverUnavailable())).step()
        job = self.client.get("/v1/link-jobs/" + job_id).json()
        self.assertEqual(job["status"], "waiting_for_operator")
        self.assertNotIn("affiliateUrl", job)
        with self.operator(ResolverStub(error=ResolverUnavailable())) as operator:
            response = operator.post("/operator/jobs/" + job_id + "/complete", json={"affiliateUrl": AFFILIATE, "verifiedProductUrl": PRODUCT, "ownershipConfirmed": True, "destinationVerified": True})
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.json()["verification"], "operator_attested_storefront_blocked")

    def test_operator_rejects_unsafe_or_missing_confirmation(self):
        job_id = self.create_and_wait()
        with self.operator() as operator:
            path = "/operator/jobs/" + job_id + "/complete"
            body = {"affiliateUrl": AFFILIATE, "verifiedProductUrl": PRODUCT, "ownershipConfirmed": False, "destinationVerified": True}
            self.assertEqual(operator.post(path, json=body).status_code, 400)
            body["ownershipConfirmed"] = True
            body["affiliateUrl"] = "https://evil.com/phishing"
            self.assertEqual(operator.post(path, json=body).status_code, 400)
            body["affiliateUrl"] = AFFILIATE
            body["verifiedProductUrl"] = "https://shopee.co.th/product/123/999"
            self.assertEqual(operator.post(path, json=body).status_code, 400)
        self.assertEqual(self.client.get("/v1/link-jobs/" + job_id).json()["status"], "waiting_for_operator")

    def test_rejected_destination_fails_with_error(self):
        job_id = self.post().json()["jobId"]
        OperatorWorker(self.store, ResolverStub(error=APIError(400, "UNSAFE_DESTINATION", "rejected"))).step()
        job = self.client.get("/v1/link-jobs/" + job_id).json()
        self.assertEqual(job["status"], "failed")
        self.assertIn("error", job)
        self.assertNotIn("affiliateUrl", job)

    def test_local_operator_auth_origin_csrf_and_api_separation(self):
        self.assertEqual(self.client.get("/operator/jobs").status_code, 404)
        with self.operator() as operator:
            operator.headers["Origin"] = "https://evil.com"
            self.assertEqual(operator.get("/operator/jobs").status_code, 403)
            operator.headers["Origin"] = "http://127.0.0.1:8081"
            operator.headers["X-CSRF-Token"] = "wrong"
            self.assertEqual(operator.post("/operator/logout").status_code, 403)
            operator.headers["Host"] = "evil.com:8081"
            self.assertEqual(operator.get("/").status_code, 403)
        with TestClient(create_admin(self.store, "x", ResolverStub()), base_url="http://127.0.0.1:8081", client=("10.0.0.3", 1000)) as remote:
            self.assertEqual(remote.get("/").status_code, 403)

    def test_error_envelope_bad_bodies_and_rate_limit(self):
        for response in [self.client.post("/v1/link-jobs", content="bad", headers={"Content-Type": "application/json"}),
                         self.client.post("/v1/link-jobs", content="x" * 17000, headers={"Content-Type": "application/json"}),
                         self.post(key="not-uuid"), self.client.get("/missing")]:
            self.assertGreaterEqual(response.status_code, 400)
            self.assertEqual(set(response.json()["error"]), {"code", "message", "retryable"})
        limiter = Limiter()
        limiter.check("key", 1)
        with self.assertRaises(APIError) as error:
            limiter.check("key", 1)
        self.assertEqual(error.exception.status, 429)
        self.assertGreater(error.exception.retry_after, 0)

    def test_queue_bound_preserves_existing_retry(self):
        self.store.max_pending = 1
        first = self.post().json()
        self.assertEqual(self.post().json()["jobId"], first["jobId"])
        response = self.post(dict(self.body, clientRequestId=str(uuid.uuid4())), str(uuid.uuid4()))
        self.assertEqual(response.status_code, 429)
        self.assertEqual(response.headers["Retry-After"], "30")

    def test_local_manual_test_form_queues_real_work(self):
        operator = TestClient(create_admin(self.store, "code", ResolverStub(), test_client_code=self.token), base_url="http://127.0.0.1:8081", client=("127.0.0.1", 9900))
        with operator:
            operator.headers["Origin"] = "http://127.0.0.1:8081"
            login = operator.post("/operator/login", json={"code": "code"})
            operator.headers["X-CSRF-Token"] = login.json()["csrfToken"]
            first = operator.post("/operator/test-jobs", json=self.body, headers={"Idempotency-Key": self.key})
            self.assertEqual(first.status_code, 202)
            self.assertEqual(first.json()["status"], "queued")
            again = operator.post("/operator/test-jobs", json=self.body, headers={"Idempotency-Key": self.key})
            self.assertEqual(first.json()["jobId"], again.json()["jobId"])
            self.assertEqual(self.client.get("/v1/link-jobs/" + first.json()["jobId"]).status_code, 200)


class URLSafetyTests(unittest.TestCase):
    def test_exact_host_and_product_identity(self):
        self.assertEqual(validate_url(PRODUCT), PRODUCT)
        self.assertEqual(product_identity(PRODUCT), ("123", "456"))
        self.assertEqual(product_identity("https://shopee.co.th/item-i.123.456?a=1"), ("123", "456"))
        for value in ["http://shope.ee/x", "https://shopee.co.th.evil.com/x", "https://user:pass@shope.ee/x",
                      "https://shopee.co.th@evil.com/x", "https://shopee.co.th:8443/x", "https://127.0.0.1/x",
                      "https://shopee.co.th\\@evil.com/x", "https://shopee.co.th/\nx", "https://shopee.co.th./x"]:
            with self.assertRaises(APIError, msg=value):
                validate_url(value)

    def test_dns_private_mixed_and_ipv6_rejected(self):
        def dns_for(addresses):
            return lambda *args, **kwargs: [(socket.AF_INET, socket.SOCK_STREAM, 6, "", (a, 443)) for a in addresses]
        for addresses in [["127.0.0.1"], ["10.0.0.1"], ["169.254.169.254"], ["8.8.8.8", "192.168.1.1"], ["::1"], ["::ffff:127.0.0.1"]]:
            with self.assertRaises(APIError):
                SafeResolver(dns=dns_for(addresses)).addresses("shope.ee")
        self.assertEqual(SafeResolver(dns=dns_for(["8.8.8.8"])).addresses("shope.ee"), ["8.8.8.8"])

    def test_redirect_allowed_and_dangerous_rejected_with_pinned_ip(self):
        calls = []
        responses = [(302, PRODUCT), (200, None)]

        class Connection:
            def __init__(self, host, address, timeout):
                calls.append((host, address))
            def request(self, *args, **kwargs):
                pass
            def getresponse(self):
                status, location = responses.pop(0)
                class Response:
                    def getheader(self, key):
                        return location
                result = Response()
                result.status = status
                return result
            def close(self):
                pass

        dns = lambda *args, **kwargs: [(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("8.8.8.8", 443))]
        resolver = SafeResolver(dns=dns, connection_factory=Connection)
        self.assertEqual(resolver.resolve(AFFILIATE), PRODUCT)
        self.assertEqual(calls, [("shope.ee", "8.8.8.8"), ("shopee.co.th", "8.8.8.8")])
        responses[:] = [(302, "https://evil.com/product/123/456")]
        with self.assertRaises(APIError):
            resolver.resolve(AFFILIATE)

    def test_bootstrap_durable_identity_and_missing_private_file(self):
        with tempfile.TemporaryDirectory() as directory:
            store, first = initialize(directory)
            reopened, second = initialize(directory)
            self.assertEqual(first["clientId"], second["clientId"])
            self.assertEqual(first["clientConnectionCode"], second["clientConnectionCode"])
            self.assertEqual(reopened.authenticate(second["clientConnectionCode"]), second["clientId"])
            Path(directory, "connection-codes.json").unlink()
            with self.assertRaises(RuntimeError):
                initialize(directory)


if __name__ == "__main__":
    unittest.main()

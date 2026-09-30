"""Read-only HTTP checks against the live local Backend; never print credentials."""
import json
from pathlib import Path

import httpx

root = Path(__file__).resolve().parents[1]
codes = json.loads((root / ".local/backend/connection-codes.json").read_text(encoding="utf-8"))
with httpx.Client(base_url="http://127.0.0.1:8080", timeout=5, trust_env=False) as client:
    assert client.get("/v1/health").status_code == 401
    client.headers["Authorization"] = "Bearer " + codes["clientConnectionCode"]
    health = client.get("/v1/health")
    assert health.status_code == 200 and health.json()["apiStatus"] == "ok"
    assert health.json()["workerStatus"] == "needs_attention"
    assert client.get("/operator/jobs").status_code == 404
with httpx.Client(base_url="http://127.0.0.1:8081", headers={"Origin": "http://127.0.0.1:8081"}, timeout=5, trust_env=False) as operator:
    assert operator.get("/").status_code == 200
    assert operator.get("/operator.js").status_code == 200
    assert operator.get("/operator.css").status_code == 200
    login = operator.post("/operator/login", json={"code": codes["adminAccessCode"]})
    assert login.status_code == 200
    operator.headers["X-CSRF-Token"] = login.json()["csrfToken"]
    assert operator.get("/operator/jobs").status_code == 200
    assert operator.get("/v1/health").status_code == 404
    assert operator.post("/operator/logout", json={}).status_code == 200
print("PASS: live loopback API auth, health, API/operator separation, dashboard assets, operator login/logout. No product jobs or affiliate results created.")

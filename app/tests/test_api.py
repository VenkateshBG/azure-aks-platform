from fastapi.testclient import TestClient

from main import app

client = TestClient(app)


def test_root():
    r = client.get("/")
    assert r.status_code == 200
    assert r.json()["service"] == "aks-platform-api"


def test_health_and_ready():
    assert client.get("/healthz").json() == {"status": "ok"}
    assert client.get("/readyz").json() == {"status": "ready"}


def test_items_crud():
    created = client.post("/items", json={"name": "widget", "quantity": 3})
    assert created.status_code == 201
    item_id = created.json()["id"]
    assert client.get(f"/items/{item_id}").json()["name"] == "widget"
    assert any(i["id"] == item_id for i in client.get("/items").json())


def test_item_not_found():
    assert client.get("/items/99999").status_code == 404


def test_burn_validates_input():
    assert client.get("/burn?seconds=0.01").status_code == 200
    assert client.get("/burn?seconds=100").status_code == 422


def test_config_check_reads_mounted_secret(tmp_path, monkeypatch):
    secret = tmp_path / "app-api-key"
    secret.write_text("s3cr3t-value\n")
    monkeypatch.setenv("API_KEY_FILE", str(secret))
    body = client.get("/config-check").json()
    assert body == {"api_key_loaded": True, "length": 12}  # value itself is never returned


def test_config_check_without_secret(monkeypatch):
    monkeypatch.setenv("API_KEY_FILE", "/nonexistent/path")
    assert client.get("/config-check").json()["api_key_loaded"] is False


def test_metrics_exposed():
    client.get("/healthz")
    body = client.get("/metrics").text
    assert "http_requests_total" in body

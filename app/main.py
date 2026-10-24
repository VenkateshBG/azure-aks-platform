"""Sample API for the AKS platform project.

Exposes:
  /            - service info
  /healthz     - liveness probe
  /readyz      - readiness probe
  /items       - tiny in-memory CRUD (demonstrates a real workload)
  /burn        - CPU-burning endpoint used to demo the HPA under load
  /metrics     - Prometheus metrics (scraped by kube-prometheus-stack)
"""
import os
import socket
import time

from fastapi import FastAPI, HTTPException, Query
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel

APP_VERSION = os.getenv("APP_VERSION", "dev")
ENVIRONMENT = os.getenv("ENVIRONMENT", "local")

app = FastAPI(title="aks-platform-api", version=APP_VERSION)

# Adds http_requests_total, http_request_duration_seconds, etc. at /metrics
Instrumentator().instrument(app).expose(app, endpoint="/metrics", include_in_schema=False)

_items: dict[int, dict] = {}
_next_id = 1


class ItemIn(BaseModel):
    name: str
    quantity: int = 1


@app.get("/")
def root():
    return {
        "service": "aks-platform-api",
        "version": APP_VERSION,
        "environment": ENVIRONMENT,
        "pod": socket.gethostname(),
    }


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    return {"status": "ready"}


@app.get("/config-check")
def config_check():
    """Proves the Key Vault secret was mounted by the CSI driver.
    Reports only whether it is present and its length - never the value."""
    path = os.getenv("API_KEY_FILE", "/mnt/secrets/app-api-key")
    try:
        with open(path) as f:
            value = f.read().strip()
        return {"api_key_loaded": bool(value), "length": len(value)}
    except OSError:
        return {"api_key_loaded": False, "length": 0}


@app.get("/items")
def list_items():
    return list(_items.values())


@app.post("/items", status_code=201)
def create_item(item: ItemIn):
    global _next_id
    record = {"id": _next_id, **item.model_dump()}
    _items[_next_id] = record
    _next_id += 1
    return record


@app.get("/items/{item_id}")
def get_item(item_id: int):
    if item_id not in _items:
        raise HTTPException(status_code=404, detail="item not found")
    return _items[item_id]


@app.get("/burn")
def burn(seconds: float = Query(0.2, ge=0, le=5)):
    """Busy-loop for `seconds` to generate CPU load (HPA demo)."""
    end = time.perf_counter() + seconds
    n = 0
    while time.perf_counter() < end:
        n += 1
    return {"burned_seconds": seconds}

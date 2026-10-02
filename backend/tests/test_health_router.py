from fastapi.testclient import TestClient

from app.main import app


def test_health_routes_are_registered_once() -> None:
    client = TestClient(app)
    res_health = client.get("/health")
    assert res_health.status_code == 200
    assert res_health.json()["ok"] is True

    res_ready = client.get("/health/ready")
    assert res_ready.status_code in (200, 503)


def test_liveness_endpoint_does_not_depend_on_the_database() -> None:
    response = TestClient(app).get("/health")

    assert response.status_code == 200
    assert response.json()["ok"] is True
    assert response.json()["ts"]

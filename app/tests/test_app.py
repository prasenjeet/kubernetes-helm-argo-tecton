import pytest
from src.app import app as flask_app


@pytest.fixture
def app():
    flask_app.config["TESTING"] = True
    yield flask_app


@pytest.fixture
def client(app):
    return app.test_client()


def test_index(client):
    resp = client.get("/")
    assert resp.status_code == 200
    data = resp.get_json()
    assert "message" in data
    assert "version" in data
    assert "environment" in data


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "healthy"}


def test_ready(client):
    resp = client.get("/ready")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ready"}

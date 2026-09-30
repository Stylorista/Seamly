from fastapi.testclient import TestClient

from app import main as main_module
from app.account_store import AccountStore
from app.google_auth import GoogleAuthError
from app.main import app


client = TestClient(app)


def test_google_login_creates_new_account(monkeypatch, tmp_path) -> None:
    monkeypatch.setattr(
        main_module, "account_store", AccountStore(tmp_path / "google_new.db")
    )
    monkeypatch.setattr(
        main_module,
        "verify_google_id_token",
        lambda token: {
            "sub": "google-sub-123",
            "email": "NewUser@Example.com",
            "name": "New User",
        },
    )
    response = client.post("/v1/auth/google", json={"id_token": "valid-token"})
    assert response.status_code == 200
    body = response.json()
    assert body["is_new_account"] is True
    assert body["profile"]["email"] == "newuser@example.com"
    assert body["profile"]["name"] == "New User"

    # Second sign-in with the same Google subject reuses the account.
    monkeypatch.setattr(
        main_module,
        "verify_google_id_token",
        lambda token: {
            "sub": "google-sub-123",
            "email": "newuser@example.com",
            "name": "New User",
        },
    )
    again = client.post("/v1/auth/google", json={"id_token": "valid-token"})
    assert again.status_code == 200
    assert again.json()["is_new_account"] is False


def test_google_login_links_existing_password_account(monkeypatch, tmp_path) -> None:
    monkeypatch.setattr(
        main_module, "account_store", AccountStore(tmp_path / "google_link.db")
    )
    registered = client.post(
        "/v1/auth/register",
        json={
            "name": "Style Tester",
            "email": "style@example.com",
            "password": "fashion123",
            "height_cm": 165,
        },
    )
    assert registered.status_code == 201

    monkeypatch.setattr(
        main_module,
        "verify_google_id_token",
        lambda token: {
            "sub": "google-sub-999",
            "email": "STYLE@example.com",
            "name": "Style Tester",
        },
    )
    response = client.post("/v1/auth/google", json={"id_token": "valid-token"})
    assert response.status_code == 200
    assert response.json()["is_new_account"] is False
    assert response.json()["profile"]["email"] == "style@example.com"


def test_google_login_rejects_invalid_token(monkeypatch, tmp_path) -> None:
    monkeypatch.setattr(
        main_module, "account_store", AccountStore(tmp_path / "google_bad.db")
    )

    def _boom(token: str):
        raise GoogleAuthError("This Google sign-in could not be verified.")

    monkeypatch.setattr(main_module, "verify_google_id_token", _boom)
    response = client.post("/v1/auth/google", json={"id_token": "bad-token-xyz"})
    assert response.status_code == 401

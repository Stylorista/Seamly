import base64
import sqlite3
from io import BytesIO

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app import main
from app.account_store import AccountStore


@pytest.fixture
def accounts(monkeypatch, tmp_path):
    store = AccountStore(tmp_path / "accounts.db")
    monkeypatch.setattr(main, "account_store", store)
    client = TestClient(main.app)
    tokens = []
    for name in ("Alice", "Bob"):
        response = client.post("/v1/auth/register", json={
            "name": name, "email": f"{name.lower()}@example.com",
            "password": "test-only-password", "height_cm": 165,
        })
        assert response.status_code == 201
        tokens.append({"Authorization": f"Bearer {response.json()['token']}"})
    return client, tokens


def _picture():
    output = BytesIO()
    Image.new("RGB", (600, 800), "#765432").save(output, format="PNG")
    return base64.b64encode(output.getvalue()).decode()


def test_profile_persists_private_picture_and_height_across_login(accounts):
    client, (alice, bob) = accounts
    updated = client.put("/v1/account/profile", headers=alice, json={
        "name": " Alice Updated ", "height_cm": 172.5, "avatar_base64": _picture(),
    })
    assert updated.status_code == 200
    profile = updated.json()
    assert profile["name"] == "Alice Updated"
    assert profile["height_cm"] == 172.5
    picture = Image.open(BytesIO(base64.b64decode(profile["avatar_base64"])))
    assert picture.format == "JPEG"
    assert max(picture.size) <= 512
    assert not picture.getexif()
    assert client.get("/v1/account/profile", headers=bob).json()["avatar_base64"] is None
    login = client.post("/v1/auth/login", json={"email": "alice@example.com", "password": "test-only-password"})
    assert login.json()["profile"]["avatar_base64"] == profile["avatar_base64"]
    assert login.json()["profile"]["height_cm"] == 172.5
    # Omission preserves the picture; an explicit null removes it.
    unchanged = client.put("/v1/account/profile", headers=alice, json={"name": "Alice", "height_cm": 172.5})
    assert unchanged.json()["avatar_base64"] == profile["avatar_base64"]
    removed = client.put("/v1/account/profile", headers=alice, json={"name": "Alice", "height_cm": 172.5, "avatar_base64": None})
    assert removed.json()["avatar_base64"] is None
    assert client.get("/v1/account/profile", headers=alice).json()["avatar_base64"] is None


def test_height_change_invalidates_old_estimates_and_rejects_stale_scan(accounts):
    client, (alice, _) = accounts
    measurements = {"height": 165, "chest": 96, "waist": 78, "hip": 104}
    payload = {"measurements": measurements, "size_label": "M"}
    assert client.put("/v1/account/measurements", headers=alice, json=payload).status_code == 200
    same = client.put("/v1/account/profile", headers=alice, json={"name": "Alice Edited", "height_cm": 165})
    assert same.json()["latest_measurements"]["waist"] == 78
    updated = client.put("/v1/account/profile", headers=alice, json={"name": "Alice Edited", "height_cm": 178})
    assert updated.json()["latest_measurements"] is None
    assert updated.json()["size_label"] is None
    assert client.put("/v1/account/measurements", headers=alice, json=payload).status_code == 409
    payload["measurements"]["height"] = 178
    assert client.put("/v1/account/measurements", headers=alice, json=payload).status_code == 200


@pytest.mark.parametrize("changes", [
    {"height_cm": 0}, {"height_cm": 231}, {"name": "  "},
    {"avatar_base64": "not an image"},
    {"avatar_base64": base64.b64encode(b"not an image").decode()},
    {"avatar_base64": "A" * 3_000_001},
])
def test_profile_rejects_invalid_updates_without_changing_account(accounts, changes):
    client, (alice, _) = accounts
    payload = {"name": "Alice", "height_cm": 165, **changes}
    assert client.put("/v1/account/profile", headers=alice, json=payload).status_code == 422
    current = client.get("/v1/account/profile", headers=alice).json()
    assert current["height_cm"] == 165
    assert current["name"] == "Alice"
    assert current["avatar_base64"] is None


def test_profile_authorization_and_current_session_logout(accounts):
    client, (alice, bob) = accounts
    payload = {"name": "Unknown", "height_cm": 175}
    assert client.put("/v1/account/profile", json=payload).status_code == 401
    assert client.put("/v1/account/profile", headers={"Authorization": "Bearer invalid"}, json=payload).status_code == 401
    assert client.post("/v1/auth/logout").status_code == 401
    assert client.post("/v1/auth/logout", headers=alice).status_code == 200
    assert client.post("/v1/auth/logout", headers=alice).status_code == 200
    assert client.get("/v1/account/profile", headers=alice).status_code == 401
    assert client.put("/v1/account/profile", headers=alice, json=payload).status_code == 401
    assert client.get("/v1/account/profile", headers=bob).status_code == 200
    assert client.post("/v1/auth/login", json={"email": "alice@example.com", "password": "test-only-password"}).status_code == 200


def test_additive_picture_schema_preserves_legacy_accounts(tmp_path):
    path = tmp_path / "legacy.db"
    with sqlite3.connect(path) as connection:
        connection.execute("""CREATE TABLE users (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, email TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL, height_cm REAL NOT NULL,
            phone TEXT, location TEXT, created_at TEXT NOT NULL
        )""")
        connection.execute("INSERT INTO users VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            ("legacy-user", "Legacy", "legacy@example.com", AccountStore._hash_password("legacy-password"), 170, None, None, "2026-09-01"))
    store = AccountStore(path)
    token, profile = store.login(email="legacy@example.com", password="legacy-password")
    assert profile["avatar_base64"] is None
    updated = store.update_profile(token=token, name="Legacy", height_cm=171)
    assert updated["id"] == "legacy-user"
    assert updated["height_cm"] == 171

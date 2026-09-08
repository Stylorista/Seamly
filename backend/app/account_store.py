from __future__ import annotations

import hashlib
import hmac
import json
import os
import secrets
import sqlite3
from datetime import UTC, datetime, timedelta
from pathlib import Path
from threading import Lock
from typing import Any
from uuid import uuid4


class AccountExistsError(ValueError):
    pass


class InvalidCredentialsError(ValueError):
    pass


class StaleMeasurementsError(ValueError):
    pass


class AccountStore:
    """Small account store with hashed passwords and revocable session tokens.

    SQLite is intentionally used so local installs work without another service.
    In production, point STYLORISTA_DB_PATH at a persistent mounted disk. The API
    stores only accepted measurements and explicitly saved account pictures;
    analysis photos are not retained.
    """

    _password_iterations = 310_000

    def __init__(self, database_path: str | Path | None = None) -> None:
        configured = str(database_path or os.getenv("STYLORISTA_DB_PATH", "")).strip()
        self._path = Path(configured) if configured else (
            Path(__file__).resolve().parents[1] / "data" / "stylorista.db"
        )
        self._schema_ready = False
        self._schema_lock = Lock()

    @property
    def storage_kind(self) -> str:
        return "sqlite"

    def register(
        self,
        *,
        name: str,
        email: str,
        password: str,
        height_cm: float,
        phone: str | None,
        location: str | None,
    ) -> tuple[str, dict[str, Any]]:
        self._ensure_schema()
        user_id = uuid4().hex
        created_at = datetime.now(UTC).isoformat()
        try:
            with self._connect() as connection:
                connection.execute(
                    """
                    INSERT INTO users (
                        id, name, email, password_hash, height_cm, phone,
                        location, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        user_id,
                        name.strip(),
                        email.strip().lower(),
                        self._hash_password(password),
                        height_cm,
                        self._clean_optional(phone),
                        self._clean_optional(location),
                        created_at,
                    ),
                )
        except sqlite3.IntegrityError as error:
            raise AccountExistsError(
                "An account already exists for this email address."
            ) from error
        token = self._create_session(user_id)
        return token, self.profile_for_token(token)

    def login(self, *, email: str, password: str) -> tuple[str, dict[str, Any]]:
        self._ensure_schema()
        with self._connect() as connection:
            row = connection.execute(
                "SELECT id, password_hash FROM users WHERE email = ?",
                (email.strip().lower(),),
            ).fetchone()
        if row is None or not self._verify_password(password, row["password_hash"]):
            raise InvalidCredentialsError("Email or password is incorrect.")
        token = self._create_session(row["id"])
        return token, self.profile_for_token(token)

    def profile_for_token(self, token: str) -> dict[str, Any]:
        self._ensure_schema()
        now = datetime.now(UTC).isoformat()
        with self._connect() as connection:
            row = connection.execute(
                """
                SELECT
                    users.id, users.name, users.email, users.phone,
                    users.location, users.height_cm, account_pictures.avatar_base64,
                    measurement_profiles.measurements_json,
                    measurement_profiles.size_label,
                    measurement_profiles.scan_confidence,
                    measurement_profiles.updated_at
                FROM sessions
                JOIN users ON users.id = sessions.user_id
                LEFT JOIN account_pictures ON account_pictures.user_id = users.id
                LEFT JOIN measurement_profiles
                    ON measurement_profiles.user_id = users.id
                WHERE sessions.token_hash = ? AND sessions.expires_at > ?
                """,
                (self._token_hash(token), now),
            ).fetchone()
        if row is None:
            raise InvalidCredentialsError("Your session has expired. Please sign in again.")
        measurements = (
            json.loads(row["measurements_json"])
            if row["measurements_json"]
            else None
        )
        return {
            "id": row["id"],
            "name": row["name"],
            "avatar_base64": row["avatar_base64"],
            "email": row["email"],
            "phone": row["phone"],
            "location": row["location"],
            "height_cm": row["height_cm"],
            "latest_measurements": measurements,
            "size_label": row["size_label"],
            "scan_confidence": row["scan_confidence"],
            "measurements_updated_at": row["updated_at"],
        }

    def save_measurements(
        self,
        *,
        token: str,
        measurements: dict[str, Any],
        size_label: str | None,
        scan_confidence: float | None,
    ) -> dict[str, Any]:
        profile = self.profile_for_token(token)
        now = datetime.now(UTC).isoformat()
        with self._connect() as connection:
            if round(float(measurements["height"]), 1) != round(float(profile["height_cm"]), 1):
                raise StaleMeasurementsError("Your height changed. Please scan again before saving measurements.")
            # Serialize height updates and scan saves on the same account row.
            updated = connection.execute(
                "UPDATE users SET height_cm = height_cm WHERE id = ? AND height_cm = ?",
                (profile["id"], profile["height_cm"]),
            )
            if updated.rowcount != 1:
                raise StaleMeasurementsError("Your height changed. Please scan again before saving measurements.")
            connection.execute(
                """
                INSERT INTO measurement_profiles (
                    user_id, measurements_json, size_label,
                    scan_confidence, updated_at
                ) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(user_id) DO UPDATE SET
                    measurements_json = excluded.measurements_json,
                    size_label = excluded.size_label,
                    scan_confidence = excluded.scan_confidence,
                    updated_at = excluded.updated_at
                """,
                (
                    profile["id"],
                    json.dumps(measurements, separators=(",", ":"), sort_keys=True),
                    self._clean_optional(size_label),
                    scan_confidence,
                    now,
                ),
            )
        return self.profile_for_token(token)

    def update_profile(
        self, *, token: str, name: str, height_cm: float,
        avatar_base64: str | None = None, update_avatar: bool = False,
    ) -> dict[str, Any]:
        profile = self.profile_for_token(token)
        with self._connect() as connection:
            # Lock the account row before checking height so concurrent saves
            # cannot restore estimates that use the previous calibration.
            connection.execute("UPDATE users SET name = ? WHERE id = ?", (name, profile["id"]))
            current = connection.execute("SELECT height_cm FROM users WHERE id = ?", (profile["id"],)).fetchone()
            if float(current["height_cm"]) != height_cm:
                connection.execute("UPDATE users SET height_cm = ? WHERE id = ?", (height_cm, profile["id"]))
                connection.execute("DELETE FROM measurement_profiles WHERE user_id = ?", (profile["id"],))
            if update_avatar:
                connection.execute(
                    """INSERT INTO account_pictures (user_id, avatar_base64) VALUES (?, ?)
                    ON CONFLICT(user_id) DO UPDATE SET avatar_base64 = excluded.avatar_base64""",
                    (profile["id"], avatar_base64),
                )
        return self.profile_for_token(token)

    def logout(self, token: str) -> None:
        self._ensure_schema()
        with self._connect() as connection:
            connection.execute("DELETE FROM sessions WHERE token_hash = ?", (self._token_hash(token),))

    @staticmethod
    def _ensure_picture_schema(connection: Any) -> None:
        connection.execute(
            """CREATE TABLE IF NOT EXISTS account_pictures (
                user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                avatar_base64 TEXT
            )"""
        )

    def _create_session(self, user_id: str) -> str:
        token = secrets.token_urlsafe(32)
        now = datetime.now(UTC)
        with self._connect() as connection:
            connection.execute(
                "DELETE FROM sessions WHERE expires_at <= ?", (now.isoformat(),)
            )
            connection.execute(
                """
                INSERT INTO sessions (
                    token_hash, user_id, created_at, expires_at
                ) VALUES (?, ?, ?, ?)
                """,
                (
                    self._token_hash(token),
                    user_id,
                    now.isoformat(),
                    (now + timedelta(days=30)).isoformat(),
                ),
            )
        return token

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self._path, timeout=15)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        return connection

    def _ensure_schema(self) -> None:
        if self._schema_ready:
            return
        with self._schema_lock:
            if self._schema_ready:
                return
            self._path.parent.mkdir(parents=True, exist_ok=True)
            with self._connect() as connection:
                connection.executescript(
                    """
                    CREATE TABLE IF NOT EXISTS users (
                        id TEXT PRIMARY KEY,
                        name TEXT NOT NULL,
                        email TEXT NOT NULL UNIQUE,
                        password_hash TEXT NOT NULL,
                        height_cm REAL NOT NULL,
                        phone TEXT,
                        location TEXT,
                        created_at TEXT NOT NULL
                    );
                    CREATE TABLE IF NOT EXISTS sessions (
                        token_hash TEXT PRIMARY KEY,
                        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                        created_at TEXT NOT NULL,
                        expires_at TEXT NOT NULL
                    );
                    CREATE TABLE IF NOT EXISTS measurement_profiles (
                        user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                        measurements_json TEXT NOT NULL,
                        size_label TEXT,
                        scan_confidence REAL,
                        updated_at TEXT NOT NULL
                    );
                    CREATE INDEX IF NOT EXISTS sessions_user_id_idx
                        ON sessions(user_id);
                    """
                )
                self._ensure_picture_schema(connection)
            self._schema_ready = True

    @classmethod
    def _hash_password(cls, password: str) -> str:
        salt = secrets.token_bytes(16)
        digest = hashlib.pbkdf2_hmac(
            "sha256", password.encode("utf-8"), salt, cls._password_iterations
        )
        return (
            f"pbkdf2_sha256${cls._password_iterations}$"
            f"{salt.hex()}${digest.hex()}"
        )

    @staticmethod
    def _verify_password(password: str, encoded: str) -> bool:
        try:
            algorithm, iterations, salt_hex, digest_hex = encoded.split("$", 3)
            if algorithm != "pbkdf2_sha256":
                return False
            candidate = hashlib.pbkdf2_hmac(
                "sha256",
                password.encode("utf-8"),
                bytes.fromhex(salt_hex),
                int(iterations),
            )
            return hmac.compare_digest(candidate, bytes.fromhex(digest_hex))
        except (ValueError, TypeError):
            return False

    @staticmethod
    def _token_hash(token: str) -> str:
        return hashlib.sha256(token.encode("utf-8")).hexdigest()

    @staticmethod
    def _clean_optional(value: str | None) -> str | None:
        normalized = (value or "").strip()
        return normalized or None


class _PostgresConnection:
    def __init__(self, connection: Any, unique_violation: type[Exception]) -> None:
        self._connection = connection
        self._unique_violation = unique_violation

    def __enter__(self) -> _PostgresConnection:
        self._connection.__enter__()
        return self

    def __exit__(self, *args: object) -> object:
        return self._connection.__exit__(*args)

    def execute(self, statement: str, parameters: tuple[Any, ...] = ()) -> Any:
        try:
            return self._connection.execute(statement.replace("?", "%s"), parameters)
        except self._unique_violation as error:
            raise sqlite3.IntegrityError(str(error)) from error


class PostgresAccountStore(AccountStore):
    """PostgreSQL variant used when DATABASE_URL is configured."""

    def __init__(self, database_url: str) -> None:
        self._database_url = database_url
        self._schema_ready = False
        self._schema_lock = Lock()

    @property
    def storage_kind(self) -> str:
        return "postgresql"

    def _connect(self) -> _PostgresConnection:
        import psycopg
        from psycopg.rows import dict_row

        connection = psycopg.connect(self._database_url, row_factory=dict_row)
        return _PostgresConnection(connection, psycopg.errors.UniqueViolation)

    def _ensure_schema(self) -> None:
        if self._schema_ready:
            return
        with self._schema_lock:
            if self._schema_ready:
                return
            with self._connect() as connection:
                connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS users (
                        id TEXT PRIMARY KEY,
                        name TEXT NOT NULL,
                        email TEXT NOT NULL UNIQUE,
                        password_hash TEXT NOT NULL,
                        height_cm DOUBLE PRECISION NOT NULL,
                        phone TEXT,
                        location TEXT,
                        created_at TEXT NOT NULL
                    )
                    """
                )
                connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS sessions (
                        token_hash TEXT PRIMARY KEY,
                        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                        created_at TEXT NOT NULL,
                        expires_at TEXT NOT NULL
                    )
                    """
                )
                connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS measurement_profiles (
                        user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                        measurements_json TEXT NOT NULL,
                        size_label TEXT,
                        scan_confidence DOUBLE PRECISION,
                        updated_at TEXT NOT NULL
                    )
                    """
                )
                connection.execute(
                    """
                    CREATE INDEX IF NOT EXISTS sessions_user_id_idx
                    ON sessions(user_id)
                    """
                )
                self._ensure_picture_schema(connection)
            self._schema_ready = True


def create_account_store() -> AccountStore:
    database_url = os.getenv("DATABASE_URL", "").strip()
    if database_url:
        return PostgresAccountStore(database_url)
    return AccountStore()

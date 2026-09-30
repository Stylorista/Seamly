from __future__ import annotations

import os


class GoogleAuthError(ValueError):
    pass


def configured_client_ids() -> list[str]:
    """Collect allowed Google OAuth client IDs from the environment.

    Supports GOOGLE_CLIENT_IDS (comma-separated) and the legacy
    GOOGLE_WEB_CLIENT_ID single value. Empty entries are ignored.
    """
    raw = os.getenv("GOOGLE_CLIENT_IDS", "") or os.getenv("GOOGLE_WEB_CLIENT_ID", "")
    return [part.strip() for part in raw.split(",") if part.strip()]


def verify_google_id_token(id_token: str) -> dict[str, str]:
    """Verify a Google OpenID Connect ID token and return user claims.

    Returns a dict with ``sub``, ``email`` and ``name``. Raises
    GoogleAuthError when verification fails or the email is not verified.
    """
    token = (id_token or "").strip()
    if not token:
        raise GoogleAuthError("A Google sign-in token is required.")
    try:
        from google.auth.transport import requests as google_requests
        from google.oauth2 import id_token as google_id_token
    except ImportError as error:
        raise GoogleAuthError(
            "Google sign-in is not configured on the server."
        ) from error

    client_ids = configured_client_ids()
    if not client_ids:
        raise GoogleAuthError("Google sign-in is not configured on the server.")
    try:
        claims = google_id_token.verify_oauth2_token(
            token, google_requests.Request(), clock_skew_in_seconds=10
        )
    except Exception as error:
        raise GoogleAuthError(
            "This Google sign-in could not be verified. Please try again."
        ) from error
    audience = str(claims.get("aud", ""))
    if audience not in client_ids:
        raise GoogleAuthError(
            "This Google sign-in was issued for a different app."
        )
    if not claims.get("email_verified", False):
        raise GoogleAuthError(
            "Your Google email address is not verified. "
            "Verify it with Google and try again."
        )
    email = str(claims.get("email", "")).strip().lower()
    subject = str(claims.get("sub", "")).strip()
    if not email or "@" not in email or not subject:
        raise GoogleAuthError(
            "This Google sign-in could not be verified. Please try again."
        )
    name = str(claims.get("name", "") or "").strip() or email.split("@")[0]
    return {"sub": subject, "email": email, "name": name[:100]}

"""Bearer session management backed by Navidrome authentication."""

import base64
import hashlib
import hmac
import secrets
import time
from dataclasses import dataclass

from fastapi import HTTPException, Request, status

from cadence.config import Settings
from cadence.db import Database


@dataclass(frozen=True, slots=True)
class UserSession:
    session_id: str
    username: str
    password: str
    expires_at: int


def _keystream(secret_key: str, nonce: bytes, length: int) -> bytes:
    out = bytearray()
    counter = 0
    key_bytes = hashlib.sha256(secret_key.encode("utf-8")).digest()
    while len(out) < length:
        block = hashlib.blake2b(
            nonce + counter.to_bytes(4, "big"),
            key=key_bytes,
            digest_size=32,
        ).digest()
        out.extend(block)
        counter += 1
    return bytes(out[:length])


def seal_password(secret_key: str, password: str) -> str:
    """Encrypt a Navidrome session password with a per-session nonce."""
    nonce = secrets.token_bytes(16)
    plain = password.encode("utf-8")
    stream = _keystream(secret_key, nonce, len(plain))
    cipher = bytes(a ^ b for a, b in zip(plain, stream, strict=True))
    mac = hmac.new(
        hashlib.sha256(secret_key.encode("utf-8")).digest(),
        nonce + cipher,
        hashlib.sha256,
    ).digest()
    return base64.urlsafe_b64encode(nonce + mac + cipher).decode("ascii")


def unseal_password(secret_key: str, blob: str) -> str:
    """Verify MAC and decrypt the sealed session password."""
    raw = base64.urlsafe_b64decode(blob.encode("ascii"))
    if len(raw) < 48:
        raise ValueError("Invalid sealed session blob")
    nonce, mac, cipher = raw[:16], raw[16:48], raw[48:]
    expected_mac = hmac.new(
        hashlib.sha256(secret_key.encode("utf-8")).digest(),
        nonce + cipher,
        hashlib.sha256,
    ).digest()
    if not hmac.compare_digest(mac, expected_mac):
        raise ValueError("Session integrity check failed")
    stream = _keystream(secret_key, nonce, len(cipher))
    plain = bytes(a ^ b for a, b in zip(cipher, stream, strict=True))
    return plain.decode("utf-8")


def sign_session_token(secret_key: str, session_id: str) -> str:
    """Create a signed bearer token '<session_id>.<hmac>'."""
    sig = hmac.new(
        secret_key.encode("utf-8"),
        session_id.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    return f"{session_id}.{sig}"


def verify_session_token(secret_key: str, token: str) -> str | None:
    """Verify token HMAC and return session_id if valid."""
    if "." not in token:
        return None
    session_id, sig = token.rsplit(".", 1)
    expected = hmac.new(
        secret_key.encode("utf-8"),
        session_id.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    if not hmac.compare_digest(sig, expected):
        return None
    return session_id


async def create_user_session(
    db: Database,
    settings: Settings,
    username: str,
    password: str,
) -> tuple[str, int]:
    """Persist an authenticated session and return (bearer_token, expires_at)."""
    session_id = secrets.token_urlsafe(24)
    expires_at = int(time.time()) + settings.session_ttl_seconds
    blob = seal_password(settings.cadence_secret_key, password)
    await db.store_auth_session(session_id, username, blob, expires_at)
    return sign_session_token(settings.cadence_secret_key, session_id), expires_at


async def require_session(request: Request) -> UserSession:
    """FastAPI dependency validating Bearer token or query ?token= (for AVPlayer streams)."""
    settings: Settings = request.app.state.settings
    auth_header = request.headers.get("Authorization", "")
    token = ""
    if auth_header.startswith("Bearer "):
        token = auth_header.removeprefix("Bearer ").strip()
    elif "token" in request.query_params:
        token = request.query_params["token"].strip()

    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Cadence session token",
        )

    session_id = verify_session_token(settings.cadence_secret_key, token)
    if not session_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Cadence session token",
        )

    db: Database = request.app.state.db
    row = await db.get_auth_session(session_id)
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session expired or unknown",
        )

    try:
        password = unseal_password(settings.cadence_secret_key, row["secret_blob"])
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session signature mismatch",
        ) from exc

    return UserSession(
        session_id=session_id,
        username=row["username"],
        password=password,
        expires_at=row["expires_at"],
    )

"""Tests for session password sealing and permanent save-to-Navidrome."""

from pathlib import Path

from fastapi.testclient import TestClient

from cadence.auth import seal_password, sign_session_token, unseal_password, verify_session_token


def test_seal_and_token_verification() -> None:
    hmac_key = "unit-fixture-hmac-material"
    blob = seal_password(hmac_key, "fixture-pw-value")
    assert "fixture-pw-value" not in blob
    assert unseal_password(hmac_key, blob) == "fixture-pw-value"

    token = sign_session_token(hmac_key, "sess-123")
    assert verify_session_token(hmac_key, token) == "sess-123"
    assert verify_session_token(hmac_key, token + "tamper") is None


def test_save_and_auto_save_star(test_client: TestClient) -> None:
    login = test_client.post(
        "/api/v1/auth/login", json={"username": "tester", "password": "secret123"}
    )
    headers = {"Authorization": f"Bearer {login.json()['token']}"}

    # Populate discovery track ext:deezer:2001 ("Shay - Nuit Blanche")
    assert test_client.get("/api/v1/home", headers=headers).status_code == 200

    # Auto-save when starring discovery track
    star_resp = test_client.post(
        "/api/v1/library/star",
        headers=headers,
        json={"track_id": "ext:deezer:2001", "starred": True, "auto_save": True},
    )
    assert star_resp.status_code == 200
    sdata = star_resp.json()
    assert sdata["starred"] is True
    assert sdata["saved_navidrome_id"] == "lib-saved-99"

    music_dir: Path = test_client.app.state.settings.cadence_music_dir
    saved_files = list((music_dir / "Cadence").rglob("*.m4a"))
    assert len(saved_files) == 1
    assert "Nuit Blanche" in saved_files[0].name

    # Playlist sync to Navidrome
    sync_resp = test_client.post("/api/v1/playlists/sync-to-navidrome", headers=headers)
    assert sync_resp.status_code == 200
    assert sync_resp.json()["synced_playlists"] >= 1

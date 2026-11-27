"""Tests for auth, capabilities, search, lyrics, and Range streaming."""

from fastapi.testclient import TestClient


def _login(client: TestClient) -> str:
    resp = client.post("/api/v1/auth/login", json={"username": "tester", "password": "secret123"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["capabilities"]["full_discovery_streaming"] is True
    return data["token"]


def test_health_and_capabilities_unauthenticated(test_client: TestClient) -> None:
    health = test_client.get("/health")
    assert health.status_code == 200
    assert health.json()["navidrome_reachable"] is True

    caps = test_client.get("/api/v1/capabilities")
    assert caps.status_code == 200
    assert caps.json()["discovery_enabled"] is True

    # Protected routes reject missing token
    home_unauth = test_client.get("/api/v1/home")
    assert home_unauth.status_code == 401


def test_login_rejects_bad_credentials(test_client: TestClient) -> None:
    resp = test_client.post("/api/v1/auth/login", json={"username": "tester", "password": "wrong"})
    assert resp.status_code == 401


def test_search_and_lyrics_and_range_streaming(test_client: TestClient) -> None:
    token = _login(test_client)
    headers = {"Authorization": f"Bearer {token}"}

    # Populate discovery DB via home
    home = test_client.get("/api/v1/home", headers=headers)
    assert home.status_code == 200

    # Unified search separates library vs discovery
    search = test_client.get("/api/v1/search?q=Zaho", headers=headers)
    assert search.status_code == 200
    sdata = search.json()
    assert len(sdata["library_tracks"]) >= 1
    assert len(sdata["discovery_tracks"]) >= 1

    # Synced lyrics lookup
    lyrics = test_client.get("/api/v1/lyrics?artist=Zaho&title=Iceberg", headers=headers)
    assert lyrics.status_code == 200
    ldata = lyrics.json()
    assert ldata["synced"] is True
    assert len(ldata["lines"]) == 2

    # HTTP Range streaming for AVPlayer on discovery track
    stream_resp = test_client.get(
        "/api/v1/stream/ext:deezer:2001",
        headers={**headers, "Range": "bytes=0-127"},
    )
    assert stream_resp.status_code == 206
    assert stream_resp.headers["content-range"].startswith("bytes 0-127/")
    assert len(stream_resp.content) == 128

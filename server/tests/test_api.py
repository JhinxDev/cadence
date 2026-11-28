"""Tests for auth, capabilities, search, suggest, lyrics, proxy headers, and Range streaming."""

import asyncio
import gzip
from pathlib import Path
from unittest.mock import patch

import httpx
from fastapi.testclient import TestClient

from cadence.models import TrackDTO
from cadence.providers.base import ResolvedAudio
from cadence.providers.command import CommandAudioProvider


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
    assert any(a["name"] == "Zaho" for a in sdata["artists"])

    # Live search suggestions
    suggest = test_client.get("/api/v1/search/suggest?q=Zaho", headers=headers)
    assert suggest.status_code == 200
    sg = suggest.json()
    assert len(sg["suggestions"]) >= 1
    assert len(sg["top_tracks"]) >= 1
    assert len(sg["top_artists"]) >= 1

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


def test_subsonic_proxy_strips_gzip_headers_after_decompression(test_client: TestClient) -> None:
    payload = b'{"subsonic-response":{"status":"ok","version":"1.16.1"}}'
    gz_body = gzip.compress(payload)
    seen_req_headers: dict[str, str] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen_req_headers.update(dict(request.headers))
        return httpx.Response(
            200,
            headers={
                "Content-Type": "application/json",
                "Content-Encoding": "gzip",
                "Content-Length": str(len(gz_body)),
            },
            content=gz_body,
        )

    transport = httpx.MockTransport(handler)
    real_async_client = httpx.AsyncClient

    def patched_async_client(*args, **kwargs):  # type: ignore[no-untyped-def]
        kwargs["transport"] = transport
        return real_async_client(*args, **kwargs)

    with patch("cadence.api.subsonic_proxy.httpx.AsyncClient", side_effect=patched_async_client):
        resp = test_client.get(
            "/rest/ping.view?v=1.16.1&c=Cadence&f=json",
            headers={"Accept-Encoding": "gzip, deflate"},
        )

    assert resp.status_code == 200
    assert seen_req_headers.get("accept-encoding") == "identity"
    assert "content-encoding" not in {k.lower() for k in resp.headers}
    assert resp.json()["subsonic-response"]["status"] == "ok"


def test_track_dto_import_clean() -> None:
    assert TrackDTO(id="1", title="T", artist="A").in_library is True


async def test_prefetch_endpoint_and_inflight_dedupe(
    test_client: TestClient, tmp_path: Path, sample_audio_file: Path
) -> None:
    token = _login(test_client)
    headers = {"Authorization": f"Bearer {token}"}

    # Warm DB via home
    home = test_client.get("/api/v1/home", headers=headers)
    assert home.status_code == 200

    prefetch = test_client.post(
        "/api/v1/stream/prefetch",
        headers=headers,
        json={"track_ids": ["ext:deezer:2001", "lib-1"]},
    )
    assert prefetch.status_code == 200
    assert "queued" in prefetch.json()

    # CommandAudioProvider deduplicates concurrent resolve_stream calls for one track
    provider = CommandAudioProvider(script_path="/nonexistent", cache_dir=tmp_path / "stream-cache")
    calls = 0

    async def fake_invoke(action: str, track: TrackDTO, output_stem: Path) -> ResolvedAudio:
        nonlocal calls
        calls += 1
        await asyncio.sleep(0.05)
        dest = output_stem.with_suffix(".m4a")
        dest.write_bytes(sample_audio_file.read_bytes())
        return ResolvedAudio(
            file_path=dest,
            mime_type="audio/mp4",
            is_preview=False,
            source_label="fake-cmd",
        )

    provider._invoke = fake_invoke  # type: ignore[method-assign]
    dto = TrackDTO(
        id="ext:deezer:9999", title="Jolie", artist="Shay", source="discovery", in_library=False
    )
    r1, r2 = await asyncio.gather(provider.resolve_stream(dto), provider.resolve_stream(dto))
    assert calls == 1
    assert r1.file_path == r2.file_path
    assert provider.is_cached("ext:deezer:9999") is True

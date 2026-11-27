"""Tests for Home feed, Mood filtering, Mixes, and Infinite Radio deduplication."""

from fastapi.testclient import TestClient

from cadence.clients.catalog import ExternalCatalogClient


def _auth_headers(client: TestClient) -> dict[str, str]:
    resp = client.post("/api/v1/auth/login", json={"username": "tester", "password": "secret123"})
    return {"Authorization": f"Bearer {resp.json()['token']}"}


def test_home_feed_dedupes_library_tracks_and_builds_mixes(test_client: TestClient) -> None:
    headers = _auth_headers(test_client)
    resp = test_client.get("/api/v1/home?mood=All", headers=headers)
    assert resp.status_code == 200
    data = resp.json()

    assert "Energize" in data["moods"]
    assert len(data["speed_dial"]) >= 2
    assert len(data["made_for_you"]) == 5

    # Ensure ext:deezer:1001 ("Zaho - Iceberg", already in library) was filtered from discovery!
    quick_ids = [t["id"] for t in data["quick_picks"]]
    assert "ext:deezer:1001" not in quick_ids
    assert "ext:deezer:2001" in quick_ids

    mix = test_client.get("/api/v1/mixes/discover-mix", headers=headers)
    assert mix.status_code == 200
    assert len(mix.json()["tracks"]) >= 2


def test_infinite_radio_modes_and_no_repeats(test_client: TestClient) -> None:
    headers = _auth_headers(test_client)
    start = test_client.post(
        "/api/v1/radio/start",
        headers=headers,
        json={
            "seed_track": {
                "id": "lib-1",
                "title": "Iceberg",
                "artist": "Zaho",
                "album": "Résilience",
                "duration_sec": 204,
                "source": "library",
                "in_library": True,
                "navidrome_id": "lib-1",
            },
            "mode": "discover",
            "count": 5,
        },
    )
    assert start.status_code == 200
    sdata = start.json()
    assert sdata["mode"] == "discover"
    first_ids = {t["id"] for t in sdata["tracks"]}
    assert "lib-1" not in first_ids
    assert len(first_ids) >= 3

    nxt = test_client.post(
        "/api/v1/radio/next",
        headers=headers,
        json={"session_id": sdata["session_id"], "count": 5},
    )
    assert nxt.status_code == 200
    next_ids = {t["id"] for t in nxt.json()["tracks"]}
    assert first_ids.isdisjoint(next_ids)


def test_lrc_parser() -> None:
    parsed = ExternalCatalogClient.parse_lrc("[00:12.34] Hello\n[01:05.5] World\ninvalid")
    assert len(parsed) == 2
    assert parsed[0].time_ms == 12340
    assert parsed[0].text == "Hello"
    assert parsed[1].time_ms == 65500

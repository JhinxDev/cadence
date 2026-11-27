"""Shared test fixtures with mocked Navidrome & external music graph responses."""

from collections.abc import AsyncIterator
from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient

from cadence.clients.catalog import ExternalCatalogClient
from cadence.clients.navidrome import NavidromeClient
from cadence.config import Settings
from cadence.db import Database
from cadence.engine.mixes import DiscoveryEngine
from cadence.main import create_app
from cadence.models import ArtistCardDTO, LyricsLineDTO, LyricsResponse, TrackDTO
from cadence.providers.base import ResolvedAudio


class FakeNavidromeClient(NavidromeClient):
    def __init__(self) -> None:
        super().__init__("http://fake-navidrome:4533")
        self.starred_calls: list[tuple[str, bool]] = []
        self.scans = 0
        self.synced_playlists: dict[str, list[str]] = {}
        self.library_songs: list[dict[str, Any]] = [
            {
                "id": "lib-1",
                "title": "Iceberg",
                "artist": "Zaho",
                "album": "Résilience",
                "duration": 204,
                "genre": "Pop",
                "year": 2023,
                "starred": "2026-11-01T00:00:00Z",
                "coverArt": "cov-1",
            },
            {
                "id": "lib-2",
                "title": "Tourner la page",
                "artist": "Zaho",
                "album": "Dima",
                "duration": 225,
                "genre": "R&B",
                "year": 2008,
                "starred": "2026-11-02T00:00:00Z",
                "coverArt": "cov-2",
            },
            {
                "id": "lib-3",
                "title": "Fairytale",
                "artist": "Alexander Rybak",
                "album": "Fairytales",
                "duration": 182,
                "genre": "Pop",
                "year": 2009,
                "coverArt": "cov-3",
            },
            {
                "id": "lib-4",
                "title": "Bâtiment",
                "artist": "Niska",
                "album": "Mr Sal",
                "duration": 210,
                "genre": "Rap",
                "year": 2019,
                "starred": "2026-11-03T00:00:00Z",
                "coverArt": "cov-4",
            },
        ]

    async def server_reachable(self) -> bool:
        return True

    async def ping(self, username: str, password: str) -> bool:
        return username == "tester" and password == "secret123"

    async def get_starred(self, username: str, password: str) -> dict[str, Any]:
        return {"song": [s for s in self.library_songs if s.get("starred")]}

    async def get_album_list(
        self, username: str, password: str, list_type: str, size: int = 20, offset: int = 0
    ) -> list[dict[str, Any]]:
        return [
            {
                "id": "alb-1",
                "name": "Résilience",
                "artist": "Zaho",
                "year": 2023,
                "songCount": 21,
                "coverArt": "cov-1",
            },
            {
                "id": "alb-2",
                "name": "Mr Sal",
                "artist": "Niska",
                "year": 2019,
                "songCount": 18,
                "coverArt": "cov-4",
            },
        ]

    async def get_album(self, username: str, password: str, album_id: str) -> dict[str, Any]:
        return {"id": album_id, "name": "Résilience", "song": self.library_songs[:2]}

    async def get_playlists(self, username: str, password: str) -> list[dict[str, Any]]:
        return [{"id": "pl-1", "name": "Liked Music", "songCount": 3, "coverArt": "cov-1"}]

    async def get_random_songs(
        self, username: str, password: str, size: int = 30, genre: str | None = None
    ) -> list[dict[str, Any]]:
        return list(self.library_songs)

    async def get_similar_songs2(
        self, username: str, password: str, item_id: str, count: int = 20
    ) -> list[dict[str, Any]]:
        return [s for s in self.library_songs if s["id"] != item_id]

    async def search(
        self,
        username: str,
        password: str,
        query: str,
        song_count: int = 20,
        album_count: int = 10,
        artist_count: int = 10,
    ) -> dict[str, Any]:
        tokens = query.lower().split()
        songs = [
            s
            for s in self.library_songs
            if all(tok in f"{s['title']} {s['artist']} {s['album']}".lower() for tok in tokens)
        ]
        return {"song": songs, "album": []}

    async def star(self, username: str, password: str, item_id: str, starred: bool = True) -> None:
        self.starred_calls.append((item_id, starred))

    async def start_scan(self, username: str, password: str) -> None:
        self.scans += 1
        self.library_songs.append(
            {
                "id": "lib-saved-99",
                "title": "Nuit Blanche",
                "artist": "Shay",
                "album": "Pourvu qu'il pleuve",
                "duration": 190,
                "coverArt": "cov-99",
            }
        )

    async def get_scan_status(self, username: str, password: str) -> bool:
        return False

    async def sync_playlist(
        self, username: str, password: str, name: str, song_ids: list[str]
    ) -> None:
        self.synced_playlists[name] = song_ids


class FakeCatalogClient(ExternalCatalogClient):
    async def get_related_artists(self, artist_name: str, limit: int = 8) -> list[ArtistCardDTO]:
        return [
            ArtistCardDTO(
                id="ext:deezer-artist:501",
                name="Shay",
                reason=f"Similar to {artist_name}",
                artwork_url="https://cdn.example/shay.jpg",
                seed_artist=artist_name,
            ),
            ArtistCardDTO(
                id="ext:deezer-artist:502",
                name="Vitaa",
                reason=f"Similar to {artist_name}",
                artwork_url="https://cdn.example/vitaa.jpg",
                seed_artist=artist_name,
            ),
        ]

    async def get_artist_top_tracks(
        self, artist_id_or_name: str, limit: int = 10, reason: str | None = None
    ) -> list[TrackDTO]:
        # Includes one duplicate of library track "Iceberg" to verify library deduplication!
        return [
            TrackDTO(
                id="ext:deezer:1001",
                title="Iceberg",
                artist="Zaho",
                album="Résilience",
                duration_sec=204,
                artwork_url="https://cdn.example/iceberg.jpg",
                source="discovery",
                in_library=False,
                is_preview=True,
                preview_url="https://cdn.example/iceberg.mp3",
                deezer_id="1001",
                reason=reason,
            ),
            TrackDTO(
                id="ext:deezer:2001",
                title="Nuit Blanche",
                artist="Shay",
                album="Pourvu qu'il pleuve",
                duration_sec=190,
                artwork_url="https://cdn.example/nuit.jpg",
                source="discovery",
                in_library=False,
                is_preview=True,
                genre="Rap",
                bpm=124.0,
                preview_url="https://cdn.example/nuit.mp3",
                deezer_id="2001",
                reason=reason or "Because you listen to Zaho",
            ),
            TrackDTO(
                id="ext:deezer:2002",
                title="À fleur de toi",
                artist="Vitaa",
                album="À fleur de toi",
                duration_sec=235,
                artwork_url="https://cdn.example/vitaa-track.jpg",
                source="discovery",
                in_library=False,
                is_preview=True,
                genre="R&B",
                bpm=92.0,
                preview_url="https://cdn.example/vitaa.mp3",
                deezer_id="2002",
                reason=reason or "Similar to Zaho",
            ),
        ]

    async def get_track_radio(
        self, artist: str, title: str, limit: int = 15, reason: str | None = None
    ) -> list[TrackDTO]:
        return [
            TrackDTO(
                id="ext:deezer:3001",
                title="Sans Réponse",
                artist="Tayc",
                album="Fleur Froide",
                duration_sec=210,
                artwork_url="https://cdn.example/tayc.jpg",
                source="discovery",
                in_library=False,
                is_preview=True,
                genre="R&B",
                preview_url="https://cdn.example/tayc.mp3",
                deezer_id="3001",
                reason=reason,
            ),
            TrackDTO(
                id="ext:deezer:3002",
                title="Petit Génie",
                artist="Jungeli",
                album="Singles",
                duration_sec=195,
                artwork_url="https://cdn.example/jungeli.jpg",
                source="discovery",
                in_library=False,
                is_preview=True,
                genre="Pop",
                preview_url="https://cdn.example/jungeli.mp3",
                deezer_id="3002",
                reason=reason,
            ),
        ]

    async def get_artist_latest_tracks(self, artist_name: str, limit: int = 4) -> list[TrackDTO]:
        return [
            TrackDTO(
                id="ext:itunes:4001",
                title="Nouveau Chapitre",
                artist=artist_name,
                album="Single 2026",
                duration_sec=188,
                artwork_url="https://cdn.example/new.jpg",
                source="discovery",
                in_library=False,
                is_preview=True,
                year=2026,
                preview_url="https://cdn.example/new.mp3",
                reason=f"Recent release from {artist_name}",
            )
        ]

    async def search_tracks(self, query: str, limit: int = 12) -> list[TrackDTO]:
        return [
            TrackDTO(
                id="ext:deezer:2001",
                title="Nuit Blanche",
                artist="Shay",
                album="Pourvu qu'il pleuve",
                duration_sec=190,
                artwork_url="https://cdn.example/nuit.jpg",
                source="discovery",
                in_library=False,
                is_preview=True,
                preview_url="https://cdn.example/nuit.mp3",
                deezer_id="2001",
                reason="Catalog discovery",
            )
        ]

    async def get_lyrics(
        self, artist: str, title: str, duration_sec: int | None = None
    ) -> LyricsResponse:
        return LyricsResponse(
            title=title,
            artist=artist,
            synced=True,
            source="lrclib",
            lines=[
                LyricsLineDTO(time_ms=1000, text="Première ligne"),
                LyricsLineDTO(time_ms=4500, text="Deuxième ligne"),
            ],
        )


class FakeCommandProvider:
    name = "command"
    supports_full_save = True

    def __init__(self, sample_file: Path) -> None:
        self.sample_file = sample_file

    async def resolve_stream(self, track: TrackDTO) -> ResolvedAudio:
        return ResolvedAudio(
            file_path=self.sample_file,
            mime_type="audio/mp4",
            is_preview=False,
            source_label="fake-full",
        )

    async def acquire_for_library(self, track: TrackDTO, target_dir: Path) -> ResolvedAudio:
        return ResolvedAudio(
            file_path=self.sample_file,
            mime_type="audio/mp4",
            is_preview=False,
            source_label="fake-full",
        )


@pytest.fixture
def sample_audio_file(tmp_path: Path) -> Path:
    audio = tmp_path / "sample.m4a"
    audio.write_bytes(b"FAKE_AUDIO_HEADER_" + b"0123456789ABCDEF" * 512)
    return audio


@pytest.fixture
def test_client(tmp_path: Path, sample_audio_file: Path) -> AsyncIterator[TestClient]:
    music_dir = tmp_path / "music"
    data_dir = tmp_path / "data"
    music_dir.mkdir(parents=True)
    data_dir.mkdir(parents=True)

    settings = Settings(
        NAVIDROME_URL="http://fake-navidrome:4533",
        CADENCE_DATA_DIR=data_dir,
        CADENCE_MUSIC_DIR=music_dir,
        CADENCE_SECRET_KEY="unit-test-secret-key-32-bytes-minimum",
        CADENCE_PROVIDER="command",
    )
    app = create_app(settings=settings)
    with TestClient(app) as client:
        db: Database = app.state.db
        fake_nav = FakeNavidromeClient()
        fake_cat = FakeCatalogClient(db=db, http_client=None)
        app.state.navidrome = fake_nav
        app.state.catalog = fake_cat
        app.state.engine = DiscoveryEngine(db=db, navidrome=fake_nav, catalog=fake_cat)
        app.state.provider = FakeCommandProvider(sample_audio_file)
        yield client

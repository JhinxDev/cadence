"""Open external music catalog & lyrics clients (Deezer, iTunes, LRCLIB) with SQLite TTL cache."""

import hashlib
import re
from typing import Any

import httpx

from cadence.db import Database
from cadence.models import ArtistCardDTO, LyricsLineDTO, LyricsResponse, TrackDTO

LRC_LINE_RE = re.compile(r"^\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]\s*(.*)$")


def make_ext_id(provider: str, raw_id: str | int) -> str:
    return f"ext:{provider}:{raw_id}"


def normalize_key(artist: str, title: str) -> str:
    """Normalize artist + title for duplicate & library matching."""

    def clean(value: str) -> str:
        lower = value.lower()
        lower = re.sub(r"\s*\((?:feat\.|ft\.|with|official|audio|video|remix)[^)]*\)", "", lower)
        lower = re.sub(r"\s*\[[^\]]*\]", "", lower)
        lower = re.sub(r"[^a-z0-9]+", " ", lower)
        return " ".join(lower.split())

    primary_artist = re.split(r",|&| feat\.| ft\.| x ", artist.lower())[0]
    return f"{clean(primary_artist)}::{clean(title)}"


class ExternalCatalogClient:
    """Async zero-API-key client for Deezer, iTunes, and LRCLIB discovery."""

    DEEZER_BASE = "https://api.deezer.com"
    ITUNES_SEARCH = "https://itunes.apple.com/search"
    LRCLIB_GET = "https://lrclib.net/api/get"

    def __init__(self, db: Database, http_client: httpx.AsyncClient | None = None) -> None:
        self.db = db
        self._client = http_client

    async def _get_json(self, url: str, params: dict[str, Any] | None = None) -> Any | None:
        cache_key = (
            "http:" + hashlib.sha256(f"{url}:{sorted((params or {}).items())}".encode()).hexdigest()
        )
        cached = await self.db.get_cache(cache_key)
        if cached is not None:
            return cached

        try:
            if self._client is not None:
                resp = await self._client.get(url, params=params, timeout=6.0)
            else:
                async with httpx.AsyncClient(timeout=6.0) as client:
                    resp = await client.get(url, params=params)
            if resp.status_code != 200:
                return None
            data = resp.json()
            if isinstance(data, dict) and "error" in data:
                return None
            await self.db.set_cache(cache_key, data, ttl_seconds=6 * 3600)
            return data
        except Exception:
            return None

    @staticmethod
    def _deezer_track_to_dto(
        item: dict[str, Any], reason: str | None = None, genre: str | None = None
    ) -> TrackDTO | None:
        tid = item.get("id")
        title = (item.get("title") or "").strip()
        artist = ((item.get("artist") or {}).get("name") or "").strip()
        if not tid or not title or not artist:
            return None
        album_obj = item.get("album") or {}
        artwork = (
            album_obj.get("cover_xl")
            or album_obj.get("cover_big")
            or album_obj.get("cover_medium")
            or (item.get("artist") or {}).get("picture_xl")
        )
        return TrackDTO(
            id=make_ext_id("deezer", tid),
            title=title,
            artist=artist,
            album=(album_obj.get("title") or "").strip(),
            duration_sec=int(item.get("duration") or 0),
            artwork_url=artwork,
            source="discovery",
            in_library=False,
            is_preview=True,
            is_starred=False,
            reason=reason,
            genre=genre,
            bpm=item.get("bpm"),
            preview_url=item.get("preview") or None,
            deezer_id=str(tid),
            isrc=item.get("isrc"),
        )

    async def search_tracks(self, query: str, limit: int = 12) -> list[TrackDTO]:
        data = await self._get_json(f"{self.DEEZER_BASE}/search", {"q": query, "limit": limit})
        if not data:
            return []
        tracks: list[TrackDTO] = []
        for item in data.get("data", []):
            dto = self._deezer_track_to_dto(item, reason="Catalog discovery")
            if dto:
                tracks.append(dto)
        return tracks

    async def find_artist(self, name: str) -> dict[str, Any] | None:
        data = await self._get_json(
            f"{self.DEEZER_BASE}/search/artist",
            {"q": name, "limit": 5},
        )
        if not data or not data.get("data"):
            return None
        target = name.strip().lower()
        for row in data["data"]:
            if (row.get("name") or "").strip().lower() == target:
                return row
        return data["data"][0]

    async def search_artists(self, query: str, limit: int = 4) -> list[ArtistCardDTO]:
        data = await self._get_json(
            f"{self.DEEZER_BASE}/search/artist",
            {"q": query, "limit": limit},
        )
        if not data or not data.get("data"):
            return []
        cards: list[ArtistCardDTO] = []
        for row in data["data"]:
            if not row.get("id") or not row.get("name"):
                continue
            cards.append(
                ArtistCardDTO(
                    id=make_ext_id("deezer-artist", row["id"]),
                    name=row["name"],
                    reason="Artist · Tap for radio",
                    artwork_url=row.get("picture_xl")
                    or row.get("picture_big")
                    or row.get("picture_medium"),
                    in_library=False,
                    seed_artist=row["name"],
                )
            )
        return cards

    async def get_related_artists(self, artist_name: str, limit: int = 8) -> list[ArtistCardDTO]:
        artist = await self.find_artist(artist_name)
        if not artist:
            return []
        data = await self._get_json(
            f"{self.DEEZER_BASE}/artist/{artist['id']}/related",
            {"limit": limit},
        )
        if not data:
            return []
        cards: list[ArtistCardDTO] = []
        for row in data.get("data", []):
            if not row.get("id") or not row.get("name"):
                continue
            cards.append(
                ArtistCardDTO(
                    id=make_ext_id("deezer-artist", row["id"]),
                    name=row["name"],
                    reason=f"Similar to {artist_name}",
                    artwork_url=row.get("picture_xl")
                    or row.get("picture_big")
                    or row.get("picture_medium"),
                    in_library=False,
                    seed_artist=artist_name,
                )
            )
        return cards

    async def get_artist_top_tracks(
        self, artist_id_or_name: str, limit: int = 10, reason: str | None = None
    ) -> list[TrackDTO]:
        artist_id = artist_id_or_name
        if artist_id.startswith("ext:deezer-artist:"):
            artist_id = artist_id.split(":")[-1]
        elif not artist_id.isdigit():
            found = await self.find_artist(artist_id_or_name)
            if not found:
                return []
            artist_id = str(found["id"])

        data = await self._get_json(
            f"{self.DEEZER_BASE}/artist/{artist_id}/top",
            {"limit": limit},
        )
        if not data:
            return []
        out: list[TrackDTO] = []
        for item in data.get("data", []):
            dto = self._deezer_track_to_dto(item, reason=reason)
            if dto:
                out.append(dto)
        return out

    async def get_track_radio(
        self, artist: str, title: str, limit: int = 15, reason: str | None = None
    ) -> list[TrackDTO]:
        matches = await self.search_tracks(f'artist:"{artist}" track:"{title}"', limit=3)
        if not matches:
            matches = await self.search_tracks(f"{artist} {title}", limit=3)
        if not matches or not matches[0].deezer_id:
            return []
        data = await self._get_json(
            f"{self.DEEZER_BASE}/track/{matches[0].deezer_id}/radio",
            {"limit": limit},
        )
        if not data:
            return []
        out: list[TrackDTO] = []
        for item in data.get("data", []):
            dto = self._deezer_track_to_dto(item, reason=reason or f"Radio from {title}")
            if dto:
                out.append(dto)
        return out

    async def get_artist_latest_tracks(self, artist_name: str, limit: int = 4) -> list[TrackDTO]:
        """Pull recent tracks from iTunes Search sorted/filtered by releaseDate."""
        data = await self._get_json(
            self.ITUNES_SEARCH,
            {"term": artist_name, "entity": "song", "limit": 12},
        )
        if not data:
            return []
        results = sorted(
            data.get("results", []),
            key=lambda r: r.get("releaseDate") or "",
            reverse=True,
        )
        out: list[TrackDTO] = []
        for row in results[:limit]:
            tid = row.get("trackId")
            title = (row.get("trackName") or "").strip()
            artist = (row.get("artistName") or "").strip()
            if not tid or not title or not artist:
                continue
            art = (row.get("artworkUrl100") or "").replace("100x100bb", "600x600bb")
            rel = (row.get("releaseDate") or "")[:4]
            out.append(
                TrackDTO(
                    id=make_ext_id("itunes", tid),
                    title=title,
                    artist=artist,
                    album=(row.get("collectionName") or "").strip(),
                    duration_sec=int((row.get("trackTimeMillis") or 0) // 1000),
                    artwork_url=art or None,
                    source="discovery",
                    in_library=False,
                    is_preview=True,
                    reason=f"Recent release from {artist}",
                    year=int(rel) if rel.isdigit() else None,
                    genre=row.get("primaryGenreName"),
                    preview_url=row.get("previewUrl"),
                )
            )
        return out

    async def get_lyrics(
        self, artist: str, title: str, duration_sec: int | None = None
    ) -> LyricsResponse:
        params: dict[str, Any] = {"artist_name": artist, "track_name": title}
        if duration_sec and duration_sec > 0:
            params["duration"] = duration_sec
        data = await self._get_json(self.LRCLIB_GET, params)
        if not data:
            return LyricsResponse(title=title, artist=artist, synced=False, source="none")

        synced_lrc = data.get("syncedLyrics")
        plain = data.get("plainLyrics")
        if isinstance(synced_lrc, str) and synced_lrc.strip():
            parsed = self.parse_lrc(synced_lrc)
            return LyricsResponse(
                title=title,
                artist=artist,
                synced=True,
                source="lrclib",
                lines=parsed,
                plain_text=plain,
            )
        if isinstance(plain, str) and plain.strip():
            lines = [LyricsLineDTO(text=line) for line in plain.splitlines()]
            return LyricsResponse(
                title=title,
                artist=artist,
                synced=False,
                source="lrclib",
                lines=lines,
                plain_text=plain,
            )
        return LyricsResponse(title=title, artist=artist, synced=False, source="none")

    @staticmethod
    def parse_lrc(lrc_text: str) -> list[LyricsLineDTO]:
        lines: list[LyricsLineDTO] = []
        for raw in lrc_text.splitlines():
            match = LRC_LINE_RE.match(raw.strip())
            if not match:
                continue
            minutes = int(match.group(1))
            seconds = int(match.group(2))
            frac_raw = match.group(3) or "0"
            millis = int(frac_raw.ljust(3, "0")[:3])
            text = match.group(4).strip()
            total_ms = (minutes * 60 + seconds) * 1000 + millis
            if text:
                lines.append(LyricsLineDTO(time_ms=total_ms, text=text))
        return lines

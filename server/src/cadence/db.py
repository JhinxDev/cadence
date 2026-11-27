"""SQLite persistence layer for Cadence cache, discovery registry, and sessions."""

import json
import time
from pathlib import Path
from typing import Any

import aiosqlite

from cadence.models import TrackDTO

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS external_cache (
    cache_key TEXT PRIMARY KEY,
    payload_json TEXT NOT NULL,
    expires_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS discovery_tracks (
    ext_id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    album TEXT NOT NULL DEFAULT '',
    duration_sec INTEGER NOT NULL DEFAULT 0,
    artwork_url TEXT,
    preview_url TEXT,
    deezer_id TEXT,
    isrc TEXT,
    bpm REAL,
    genres_json TEXT NOT NULL DEFAULT '[]',
    navidrome_id TEXT,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS radio_sessions (
    session_id TEXT PRIMARY KEY,
    username TEXT NOT NULL,
    seed_json TEXT NOT NULL,
    mode TEXT NOT NULL,
    served_keys_json TEXT NOT NULL,
    created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS auth_sessions (
    session_id TEXT PRIMARY KEY,
    username TEXT NOT NULL,
    secret_blob TEXT NOT NULL,
    expires_at INTEGER NOT NULL,
    created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS taste_snapshots (
    username TEXT PRIMARY KEY,
    payload_json TEXT NOT NULL,
    updated_at INTEGER NOT NULL
);
"""


class Database:
    """Async SQLite store managing Cadence runtime state."""

    def __init__(self, db_path: Path) -> None:
        self.db_path = db_path
        self._conn: aiosqlite.Connection | None = None

    async def connect(self) -> None:
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._conn = await aiosqlite.connect(self.db_path)
        self._conn.row_factory = aiosqlite.Row
        await self._conn.execute("PRAGMA journal_mode=WAL;")
        await self._conn.executescript(SCHEMA_SQL)
        await self._conn.commit()

    async def close(self) -> None:
        if self._conn is not None:
            await self._conn.close()
            self._conn = None

    @property
    def conn(self) -> aiosqlite.Connection:
        if self._conn is None:
            raise RuntimeError("Database is not connected")
        return self._conn

    async def get_cache(self, key: str) -> Any | None:
        now = int(time.time())
        async with self.conn.execute(
            "SELECT payload_json, expires_at FROM external_cache WHERE cache_key = ?",
            (key,),
        ) as cur:
            row = await cur.fetchone()
        if row is None or int(row["expires_at"]) < now:
            return None
        return json.loads(row["payload_json"])

    async def set_cache(self, key: str, payload: Any, ttl_seconds: int = 3600) -> None:
        expires_at = int(time.time()) + ttl_seconds
        await self.conn.execute(
            """
            INSERT INTO external_cache(cache_key, payload_json, expires_at)
            VALUES(?, ?, ?)
            ON CONFLICT(cache_key) DO UPDATE SET
                payload_json = excluded.payload_json,
                expires_at = excluded.expires_at
            """,
            (key, json.dumps(payload), expires_at),
        )
        await self.conn.commit()

    async def upsert_discovery_track(self, track: TrackDTO) -> None:
        now = int(time.time())
        genres = [track.genre] if track.genre else []
        await self.conn.execute(
            """
            INSERT INTO discovery_tracks(
                ext_id, title, artist, album, duration_sec, artwork_url,
                preview_url, deezer_id, isrc, bpm, genres_json, navidrome_id, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(ext_id) DO UPDATE SET
                title = excluded.title,
                artist = excluded.artist,
                album = excluded.album,
                duration_sec = excluded.duration_sec,
                artwork_url = COALESCE(excluded.artwork_url, discovery_tracks.artwork_url),
                preview_url = COALESCE(excluded.preview_url, discovery_tracks.preview_url),
                deezer_id = COALESCE(excluded.deezer_id, discovery_tracks.deezer_id),
                isrc = COALESCE(excluded.isrc, discovery_tracks.isrc),
                bpm = COALESCE(excluded.bpm, discovery_tracks.bpm),
                navidrome_id = COALESCE(excluded.navidrome_id, discovery_tracks.navidrome_id),
                updated_at = excluded.updated_at
            """,
            (
                track.id,
                track.title,
                track.artist,
                track.album,
                track.duration_sec,
                track.artwork_url,
                track.preview_url,
                track.deezer_id,
                track.isrc,
                track.bpm,
                json.dumps(genres),
                track.navidrome_id,
                now,
            ),
        )
        await self.conn.commit()

    async def upsert_discovery_tracks(self, tracks: list[TrackDTO]) -> None:
        for track in tracks:
            if track.source == "discovery":
                await self.upsert_discovery_track(track)

    async def get_discovery_track(self, ext_id: str) -> TrackDTO | None:
        async with self.conn.execute(
            "SELECT * FROM discovery_tracks WHERE ext_id = ?",
            (ext_id,),
        ) as cur:
            row = await cur.fetchone()
        if row is None:
            return None
        genres = json.loads(row["genres_json"] or "[]")
        nav_id = row["navidrome_id"]
        return TrackDTO(
            id=row["ext_id"],
            title=row["title"],
            artist=row["artist"],
            album=row["album"] or "",
            duration_sec=int(row["duration_sec"] or 0),
            artwork_url=row["artwork_url"],
            source="discovery",
            in_library=bool(nav_id),
            is_preview=not bool(nav_id),
            navidrome_id=nav_id,
            genre=genres[0] if genres else None,
            bpm=row["bpm"],
            preview_url=row["preview_url"],
            deezer_id=row["deezer_id"],
            isrc=row["isrc"],
        )

    async def mark_discovery_saved(self, ext_id: str, navidrome_id: str) -> None:
        now = int(time.time())
        await self.conn.execute(
            "UPDATE discovery_tracks SET navidrome_id = ?, updated_at = ? WHERE ext_id = ?",
            (navidrome_id, now, ext_id),
        )
        await self.conn.commit()

    async def save_radio_session(
        self,
        session_id: str,
        username: str,
        seed: dict[str, Any],
        mode: str,
        served_keys: list[str],
    ) -> None:
        now = int(time.time())
        await self.conn.execute(
            """
            INSERT INTO radio_sessions(
                session_id, username, seed_json, mode, served_keys_json, created_at
            )
            VALUES(?, ?, ?, ?, ?, ?)
            ON CONFLICT(session_id) DO UPDATE SET
                mode = excluded.mode,
                served_keys_json = excluded.served_keys_json
            """,
            (session_id, username, json.dumps(seed), mode, json.dumps(served_keys), now),
        )
        await self.conn.commit()

    async def get_radio_session(self, session_id: str, username: str) -> dict[str, Any] | None:
        async with self.conn.execute(
            "SELECT * FROM radio_sessions WHERE session_id = ? AND username = ?",
            (session_id, username),
        ) as cur:
            row = await cur.fetchone()
        if row is None:
            return None
        return {
            "session_id": row["session_id"],
            "username": row["username"],
            "seed": json.loads(row["seed_json"]),
            "mode": row["mode"],
            "served_keys": json.loads(row["served_keys_json"]),
        }

    async def store_auth_session(
        self, session_id: str, username: str, secret_blob: str, expires_at: int
    ) -> None:
        now = int(time.time())
        await self.conn.execute(
            """
            INSERT INTO auth_sessions(session_id, username, secret_blob, expires_at, created_at)
            VALUES(?, ?, ?, ?, ?)
            """,
            (session_id, username, secret_blob, expires_at, now),
        )
        await self.conn.commit()

    async def get_auth_session(self, session_id: str) -> dict[str, Any] | None:
        now = int(time.time())
        async with self.conn.execute(
            "SELECT * FROM auth_sessions WHERE session_id = ? AND expires_at > ?",
            (session_id, now),
        ) as cur:
            row = await cur.fetchone()
        if row is None:
            return None
        return {
            "session_id": row["session_id"],
            "username": row["username"],
            "secret_blob": row["secret_blob"],
            "expires_at": int(row["expires_at"]),
        }

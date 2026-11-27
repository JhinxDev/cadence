"""Async OpenSubsonic 1.16.1 client for Navidrome + Maestro integration."""

import hashlib
import secrets
from typing import Any
from urllib.parse import urlencode

import httpx

from cadence.models import AlbumCardDTO, TrackDTO


class NavidromeError(RuntimeError):
    """Raised when Navidrome rejects or fails a Subsonic API call."""


class NavidromeClient:
    """Thin async client around Navidrome's OpenSubsonic endpoints."""

    def __init__(self, base_url: str, http_client: httpx.AsyncClient | None = None) -> None:
        self.base_url = base_url.rstrip("/")
        self._client = http_client

    @staticmethod
    def _auth_params(username: str, password: str) -> dict[str, str]:
        salt = secrets.token_hex(6)
        token = hashlib.md5(f"{password}{salt}".encode()).hexdigest()
        return {
            "u": username,
            "t": token,
            "s": salt,
            "v": "1.16.1",
            "c": "Cadence",
            "f": "json",
        }

    def build_url(
        self, endpoint: str, username: str, password: str, extra: dict[str, Any] | None = None
    ) -> str:
        params = self._auth_params(username, password)
        if extra:
            for k, v in extra.items():
                if v is not None:
                    params[k] = str(v)
        return f"{self.base_url}/rest/{endpoint}?{urlencode(params)}"

    async def _call(
        self,
        endpoint: str,
        username: str,
        password: str,
        params: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        query = self._auth_params(username, password)
        if params:
            for k, v in params.items():
                if v is not None:
                    query[k] = str(v)

        url = f"{self.base_url}/rest/{endpoint}"
        if self._client is not None:
            resp = await self._client.get(url, params=query, timeout=10.0)
        else:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.get(url, params=query)

        resp.raise_for_status()
        payload = resp.json().get("subsonic-response", {})
        if payload.get("status") != "ok":
            err = payload.get("error", {})
            raise NavidromeError(err.get("message", f"Navidrome error on {endpoint}"))
        return payload

    async def ping(self, username: str, password: str) -> bool:
        try:
            await self._call("ping.view", username, password)
            return True
        except Exception:
            return False

    async def server_reachable(self) -> bool:
        url = f"{self.base_url}/ping"
        try:
            if self._client is not None:
                resp = await self._client.get(url, timeout=3.0)
            else:
                async with httpx.AsyncClient(timeout=3.0) as client:
                    resp = await client.get(url)
            return resp.status_code < 500
        except Exception:
            return False

    @staticmethod
    def song_to_dto(song: dict[str, Any], reason: str | None = None) -> TrackDTO:
        song_id = str(song["id"])
        cover_id = song.get("coverArt") or song_id
        return TrackDTO(
            id=song_id,
            title=song.get("title") or "Untitled",
            artist=song.get("artist") or "Unknown Artist",
            album=song.get("album") or "",
            duration_sec=int(song.get("duration") or 0),
            artwork_url=f"/api/v1/artwork/{cover_id}" if cover_id else None,
            source="library",
            in_library=True,
            is_preview=False,
            is_starred=bool(song.get("starred")),
            reason=reason,
            navidrome_id=song_id,
            year=song.get("year"),
            genre=song.get("genre"),
            bpm=song.get("bpm"),
        )

    @staticmethod
    def album_to_dto(album: dict[str, Any]) -> AlbumCardDTO:
        album_id = str(album["id"])
        cover_id = album.get("coverArt") or album_id
        return AlbumCardDTO(
            id=album_id,
            title=album.get("name") or album.get("title") or "Untitled Album",
            artist=album.get("artist") or "Unknown Artist",
            year=album.get("year"),
            song_count=int(album.get("songCount") or 0),
            artwork_url=f"/api/v1/artwork/{cover_id}" if cover_id else None,
        )

    async def get_starred(self, username: str, password: str) -> dict[str, Any]:
        data = await self._call("getStarred2.view", username, password)
        return data.get("starred2", {})

    async def get_album_list(
        self, username: str, password: str, list_type: str, size: int = 20, offset: int = 0
    ) -> list[dict[str, Any]]:
        data = await self._call(
            "getAlbumList2.view",
            username,
            password,
            {"type": list_type, "size": size, "offset": offset},
        )
        return data.get("albumList2", {}).get("album", [])

    async def get_album(self, username: str, password: str, album_id: str) -> dict[str, Any]:
        data = await self._call("getAlbum.view", username, password, {"id": album_id})
        return data.get("album", {})

    async def get_playlists(self, username: str, password: str) -> list[dict[str, Any]]:
        data = await self._call("getPlaylists.view", username, password)
        return data.get("playlists", {}).get("playlist", [])

    async def get_playlist(self, username: str, password: str, playlist_id: str) -> dict[str, Any]:
        data = await self._call("getPlaylist.view", username, password, {"id": playlist_id})
        return data.get("playlist", {})

    async def get_random_songs(
        self, username: str, password: str, size: int = 30, genre: str | None = None
    ) -> list[dict[str, Any]]:
        params: dict[str, Any] = {"size": size}
        if genre:
            params["genre"] = genre
        data = await self._call("getRandomSongs.view", username, password, params)
        return data.get("randomSongs", {}).get("song", [])

    async def get_similar_songs2(
        self, username: str, password: str, item_id: str, count: int = 20
    ) -> list[dict[str, Any]]:
        try:
            data = await self._call(
                "getSimilarSongs2.view",
                username,
                password,
                {"id": item_id, "count": count},
            )
            return data.get("similarSongs2", {}).get("song", [])
        except Exception:
            return []

    async def search(
        self,
        username: str,
        password: str,
        query: str,
        song_count: int = 20,
        album_count: int = 10,
        artist_count: int = 10,
    ) -> dict[str, Any]:
        data = await self._call(
            "search3.view",
            username,
            password,
            {
                "query": query,
                "songCount": song_count,
                "albumCount": album_count,
                "artistCount": artist_count,
            },
        )
        return data.get("searchResult3", {})

    async def star(self, username: str, password: str, item_id: str, starred: bool = True) -> None:
        endpoint = "star.view" if starred else "unstar.view"
        await self._call(endpoint, username, password, {"id": item_id})

    async def start_scan(self, username: str, password: str) -> None:
        await self._call("startScan.view", username, password)

    async def get_scan_status(self, username: str, password: str) -> bool:
        data = await self._call("getScanStatus.view", username, password)
        return bool(data.get("scanStatus", {}).get("scanning", False))

    async def get_lyrics(self, username: str, password: str, artist: str, title: str) -> str | None:
        try:
            data = await self._call(
                "getLyrics.view",
                username,
                password,
                {"artist": artist, "title": title},
            )
            lyrics = data.get("lyrics", {})
            value = lyrics.get("value")
            return value.strip() if isinstance(value, str) and value.strip() else None
        except Exception:
            return None

    async def sync_playlist(
        self, username: str, password: str, name: str, song_ids: list[str]
    ) -> None:
        if not song_ids:
            return
        playlists = await self.get_playlists(username, password)
        existing = next((p for p in playlists if p.get("name") == name), None)
        query = self._auth_params(username, password)
        params: list[tuple[str, str]] = list(query.items())
        if existing:
            params.append(("playlistId", str(existing["id"])))
        else:
            params.append(("name", name))
        for sid in song_ids:
            params.append(("songId", sid))

        url = f"{self.base_url}/rest/createPlaylist.view"
        if self._client is not None:
            resp = await self._client.get(url, params=params, timeout=10.0)
        else:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.get(url, params=params)
        resp.raise_for_status()

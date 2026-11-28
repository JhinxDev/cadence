"""Core /api/v1 REST routes for the Cadence iOS client."""

import asyncio
from collections.abc import AsyncIterator
from pathlib import Path

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from fastapi.responses import Response, StreamingResponse

from cadence import __version__
from cadence.auth import UserSession, create_user_session, require_session
from cadence.clients.catalog import ExternalCatalogClient, normalize_key
from cadence.clients.navidrome import NavidromeClient
from cadence.config import Settings
from cadence.db import Database
from cadence.engine.mixes import DiscoveryEngine
from cadence.engine.saver import save_discovery_track
from cadence.engine.taste import build_taste_profile
from cadence.models import (
    CapabilitiesResponse,
    HomeFeedResponse,
    LoginRequest,
    LoginResponse,
    LyricsLineDTO,
    LyricsResponse,
    MixDetailResponse,
    PrefetchRequest,
    RadioNextRequest,
    RadioResponse,
    RadioStartRequest,
    SaveTrackRequest,
    SaveTrackResponse,
    SearchResponse,
    SearchSuggestResponse,
    StarTrackRequest,
    StarTrackResponse,
    TrackDTO,
)
from cadence.providers.base import AudioProvider

router = APIRouter(prefix="/api/v1", tags=["cadence"])


def _capabilities(settings: Settings) -> CapabilitiesResponse:
    is_command = settings.cadence_provider.lower() == "command"
    return CapabilitiesResponse(
        service="cadence",
        version=__version__,
        discovery_enabled=True,
        full_discovery_streaming=is_command,
        save_to_library_enabled=is_command,
        lyrics_enabled=True,
        subsonic_proxy_enabled=True,
    )


def _get_engine(request: Request) -> DiscoveryEngine:
    return request.app.state.engine


def _get_navidrome(request: Request) -> NavidromeClient:
    return request.app.state.navidrome


def _get_catalog(request: Request) -> ExternalCatalogClient:
    return request.app.state.catalog


def _get_db(request: Request) -> Database:
    return request.app.state.db


def _get_provider(request: Request) -> AudioProvider:
    return request.app.state.provider


def _get_settings(request: Request) -> Settings:
    return request.app.state.settings


@router.get("/capabilities", response_model=CapabilitiesResponse)
async def get_capabilities(request: Request) -> CapabilitiesResponse:
    return _capabilities(_get_settings(request))


@router.post("/auth/login", response_model=LoginResponse)
async def login(
    payload: LoginRequest,
    request: Request,
) -> LoginResponse:
    settings = _get_settings(request)
    navidrome = _get_navidrome(request)
    ok = await navidrome.ping(payload.username, payload.password)
    if not ok:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Navidrome username or password",
        )
    db = _get_db(request)
    token, expires_at = await create_user_session(db, settings, payload.username, payload.password)
    return LoginResponse(
        token=token,
        username=payload.username,
        expires_at=expires_at,
        capabilities=_capabilities(settings),
    )


def _schedule_provider_prefetch(
    provider: AudioProvider, tracks: list[TrackDTO], limit: int = 3
) -> int:
    sched = getattr(provider, "schedule_prefetch", None)
    if callable(sched):
        return int(sched(tracks, limit=limit))
    return 0


@router.get("/home", response_model=HomeFeedResponse)
async def get_home(
    request: Request,
    mood: str = Query(default="All"),
    session: UserSession = Depends(require_session),
) -> HomeFeedResponse:
    engine = _get_engine(request)
    feed = await engine.build_home(session.username, session.password, mood=mood)
    _schedule_provider_prefetch(
        _get_provider(request),
        [t for t in feed.quick_picks if not t.in_library],
        limit=2,
    )
    return feed


@router.get("/mixes/{mix_id}", response_model=MixDetailResponse)
async def get_mix(
    mix_id: str,
    request: Request,
    mood: str = Query(default="All"),
    session: UserSession = Depends(require_session),
) -> MixDetailResponse:
    engine = _get_engine(request)
    detail = await engine.build_mix(session.username, session.password, mix_id=mix_id, mood=mood)
    _schedule_provider_prefetch(
        _get_provider(request),
        [t for t in detail.tracks if not t.in_library],
        limit=3,
    )
    return detail


@router.post("/radio/start", response_model=RadioResponse)
async def start_radio(
    payload: RadioStartRequest,
    request: Request,
    session: UserSession = Depends(require_session),
) -> RadioResponse:
    engine = _get_engine(request)
    batch = await engine.start_radio(
        username=session.username,
        password=session.password,
        seed_track=payload.seed_track,
        seed_artist=payload.seed_artist,
        mood=payload.mood,
        mode=payload.mode,
        count=payload.count,
    )
    _schedule_provider_prefetch(
        _get_provider(request),
        [t for t in batch.tracks if not t.in_library],
        limit=3,
    )
    return batch


@router.post("/radio/next", response_model=RadioResponse)
async def next_radio(
    payload: RadioNextRequest,
    request: Request,
    session: UserSession = Depends(require_session),
) -> RadioResponse:
    engine = _get_engine(request)
    batch = await engine.next_radio(
        username=session.username,
        password=session.password,
        session_id=payload.session_id,
        mode_override=payload.mode,
        count=payload.count,
    )
    _schedule_provider_prefetch(
        _get_provider(request),
        [t for t in batch.tracks if not t.in_library],
        limit=3,
    )
    return batch


@router.post("/stream/prefetch")
async def prefetch_streams(
    payload: PrefetchRequest,
    request: Request,
    session: UserSession = Depends(require_session),
) -> dict[str, int]:
    _ = session
    db = _get_db(request)
    provider = _get_provider(request)
    tracks: list[TrackDTO] = []
    for tid in payload.track_ids:
        if not tid.startswith("ext:"):
            continue
        track = await db.get_discovery_track(tid)
        if track is not None:
            tracks.append(track)
    queued = _schedule_provider_prefetch(provider, tracks, limit=3)
    return {"queued": queued}


@router.get("/search/suggest", response_model=SearchSuggestResponse)
async def search_suggest(
    request: Request,
    q: str = Query(min_length=1, max_length=120),
    session: UserSession = Depends(require_session),
) -> SearchSuggestResponse:
    navidrome = _get_navidrome(request)
    catalog = _get_catalog(request)
    db = _get_db(request)

    nav_res, ext_tracks_res, ext_artists_res, profile_res = await asyncio.gather(
        navidrome.search(session.username, session.password, q, song_count=5, album_count=3),
        catalog.search_tracks(q, limit=6),
        catalog.search_artists(q, limit=4),
        build_taste_profile(navidrome, session.username, session.password),
        return_exceptions=True,
    )

    res = nav_res if isinstance(nav_res, dict) else {}
    lib_tracks = [navidrome.song_to_dto(s) for s in res.get("song", [])]
    library_keys = profile_res.library_keys if not isinstance(profile_res, BaseException) else set()
    ext_raw = ext_tracks_res if isinstance(ext_tracks_res, list) else []
    disc_tracks = [t for t in ext_raw if normalize_key(t.artist, t.title) not in library_keys]
    if disc_tracks:
        await db.upsert_discovery_tracks(disc_tracks)

    top_artists = ext_artists_res if isinstance(ext_artists_res, list) else []

    seen_suggestions: set[str] = set()
    suggestions: list[str] = []

    def add_suggestion(candidate: str) -> None:
        cleaned = " ".join(candidate.split()).strip()
        key = cleaned.lower()
        if cleaned and key not in seen_suggestions and len(suggestions) < 6:
            seen_suggestions.add(key)
            suggestions.append(cleaned)

    for artist in top_artists:
        add_suggestion(artist.name)
    for track in lib_tracks[:3]:
        add_suggestion(f"{track.artist} - {track.title}")
    for track in disc_tracks[:4]:
        add_suggestion(f"{track.artist} - {track.title}")

    combined_tracks: list = []
    seen_track_keys: set[str] = set()
    for track in [*lib_tracks, *disc_tracks]:
        tk = normalize_key(track.artist, track.title)
        if tk in seen_track_keys:
            continue
        seen_track_keys.add(tk)
        combined_tracks.append(track)
        if len(combined_tracks) >= 5:
            break

    return SearchSuggestResponse(
        query=q,
        suggestions=suggestions[:6],
        top_tracks=combined_tracks,
        top_artists=top_artists[:4],
    )


@router.get("/search", response_model=SearchResponse)
async def unified_search(
    request: Request,
    q: str = Query(min_length=1, max_length=120),
    session: UserSession = Depends(require_session),
) -> SearchResponse:
    navidrome = _get_navidrome(request)
    catalog = _get_catalog(request)
    db = _get_db(request)

    (
        res_raw,
        profile_res,
        ext_raw_res,
        exact_artists_res,
        related_artists_res,
    ) = await asyncio.gather(
        navidrome.search(session.username, session.password, q, song_count=15, album_count=8),
        build_taste_profile(navidrome, session.username, session.password),
        catalog.search_tracks(q, limit=15),
        catalog.search_artists(q, limit=4),
        catalog.get_related_artists(q, limit=6),
        return_exceptions=True,
    )

    res = res_raw if isinstance(res_raw, dict) else {}
    lib_tracks = [navidrome.song_to_dto(s) for s in res.get("song", [])]
    lib_albums = [navidrome.album_to_dto(a) for a in res.get("album", [])]

    library_keys = profile_res.library_keys if not isinstance(profile_res, BaseException) else set()
    ext_raw = ext_raw_res if isinstance(ext_raw_res, list) else []
    disc_tracks = [t for t in ext_raw if normalize_key(t.artist, t.title) not in library_keys]
    await db.upsert_discovery_tracks(disc_tracks)

    artists = []
    seen_artist_names: set[str] = set()
    for artist in [
        *(exact_artists_res if isinstance(exact_artists_res, list) else []),
        *(related_artists_res if isinstance(related_artists_res, list) else []),
    ]:
        key = artist.name.strip().lower()
        if key and key not in seen_artist_names:
            seen_artist_names.add(key)
            artists.append(artist)

    return SearchResponse(
        query=q,
        library_tracks=lib_tracks,
        discovery_tracks=disc_tracks,
        library_albums=lib_albums,
        artists=artists[:8],
    )


@router.get("/lyrics", response_model=LyricsResponse)
async def get_lyrics(
    request: Request,
    artist: str = Query(min_length=1),
    title: str = Query(min_length=1),
    duration_sec: int | None = Query(default=None),
    session: UserSession = Depends(require_session),
) -> LyricsResponse:
    catalog = _get_catalog(request)
    lrclib = await catalog.get_lyrics(artist, title, duration_sec=duration_sec)
    if lrclib.lines:
        return lrclib

    navidrome = _get_navidrome(request)
    nav_lyrics = await navidrome.get_lyrics(session.username, session.password, artist, title)
    if nav_lyrics:
        lines = [LyricsLineDTO(text=line) for line in nav_lyrics.splitlines() if line.strip()]
        return LyricsResponse(
            title=title,
            artist=artist,
            synced=False,
            source="navidrome",
            lines=lines,
            plain_text=nav_lyrics,
        )
    return lrclib


def _stream_file_range(
    path: Path, start: int, end: int, chunk_size: int = 65536
) -> AsyncIterator[bytes]:
    async def iterator() -> AsyncIterator[bytes]:
        remaining = end - start + 1
        with path.open("rb") as f:
            f.seek(start)
            while remaining > 0:
                chunk = f.read(min(chunk_size, remaining))
                if not chunk:
                    break
                remaining -= len(chunk)
                yield chunk

    return iterator()


@router.get("/stream/{track_id}")
async def stream_track(
    track_id: str,
    request: Request,
    session: UserSession = Depends(require_session),
) -> Response:
    navidrome = _get_navidrome(request)
    db = _get_db(request)
    provider = _get_provider(request)

    if not track_id.startswith("ext:"):
        url = navidrome.build_url(
            "stream.view", session.username, session.password, {"id": track_id}
        )
        return await _proxy_upstream_stream(url, request.headers.get("range"))

    track = await db.get_discovery_track(track_id)
    if track is None:
        raise HTTPException(status_code=404, detail="Unknown discovery track")

    if track.navidrome_id:
        url = navidrome.build_url(
            "stream.view", session.username, session.password, {"id": track.navidrome_id}
        )
        return await _proxy_upstream_stream(url, request.headers.get("range"))

    resolved = await provider.resolve_stream(track)
    if resolved.file_path is not None and resolved.file_path.exists():
        size = resolved.file_path.stat().st_size
        range_header = request.headers.get("range")
        if range_header and range_header.startswith("bytes="):
            spec = range_header.removeprefix("bytes=").split(",")[0].strip()
            start_str, _, end_str = spec.partition("-")
            start = int(start_str) if start_str else 0
            end = int(end_str) if end_str else size - 1
            end = min(end, size - 1)
            if start > end or start >= size:
                raise HTTPException(status_code=416, detail="Requested range not satisfiable")
            headers = {
                "Content-Range": f"bytes {start}-{end}/{size}",
                "Accept-Ranges": "bytes",
                "Content-Length": str(end - start + 1),
            }
            return StreamingResponse(
                _stream_file_range(resolved.file_path, start, end),
                status_code=206,
                media_type=resolved.mime_type,
                headers=headers,
            )

        return StreamingResponse(
            _stream_file_range(resolved.file_path, 0, size - 1),
            status_code=200,
            media_type=resolved.mime_type,
            headers={"Accept-Ranges": "bytes", "Content-Length": str(size)},
        )

    if resolved.remote_url:
        return await _proxy_upstream_stream(resolved.remote_url, request.headers.get("range"))

    raise HTTPException(status_code=502, detail="Unable to resolve discovery stream")


async def _proxy_upstream_stream(url: str, range_header: str | None) -> Response:
    req_headers: dict[str, str] = {}
    if range_header:
        req_headers["Range"] = range_header

    client = httpx.AsyncClient(timeout=30.0, follow_redirects=True)
    req = client.build_request("GET", url, headers=req_headers)
    upstream = await client.send(req, stream=True)

    passthrough = {}
    for hdr in ("content-type", "content-length", "content-range", "accept-ranges"):
        if hdr in upstream.headers:
            passthrough[hdr.title()] = upstream.headers[hdr]

    async def body_iter() -> AsyncIterator[bytes]:
        try:
            async for chunk in upstream.aiter_bytes(65536):
                yield chunk
        finally:
            await upstream.aclose()
            await client.aclose()

    return StreamingResponse(
        body_iter(),
        status_code=upstream.status_code,
        headers=passthrough,
        media_type=upstream.headers.get("content-type", "audio/mpeg"),
    )


@router.get("/artwork/{art_id}")
async def get_artwork(
    art_id: str,
    request: Request,
    size: int = Query(default=600, ge=64, le=1200),
    session: UserSession = Depends(require_session),
) -> Response:
    navidrome = _get_navidrome(request)
    url = navidrome.build_url(
        "getCoverArt.view",
        session.username,
        session.password,
        {"id": art_id, "size": size},
    )
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(url)
    if resp.status_code != 200:
        raise HTTPException(status_code=404, detail="Artwork not found")
    return Response(
        content=resp.content,
        media_type=resp.headers.get("content-type", "image/jpeg"),
        headers={"Cache-Control": "public, max-age=86400"},
    )


@router.post("/library/save", response_model=SaveTrackResponse)
async def save_track(
    payload: SaveTrackRequest,
    request: Request,
    session: UserSession = Depends(require_session),
) -> SaveTrackResponse:
    settings = _get_settings(request)
    db = _get_db(request)
    navidrome = _get_navidrome(request)
    provider = _get_provider(request)

    if not payload.track_id.startswith("ext:"):
        if payload.star:
            await navidrome.star(session.username, session.password, payload.track_id, starred=True)
        return SaveTrackResponse(
            status="already_in_library",
            track_id=payload.track_id,
            navidrome_id=payload.track_id,
        )

    track = await db.get_discovery_track(payload.track_id)
    if track is None:
        raise HTTPException(status_code=404, detail="Discovery track not found")

    if not getattr(provider, "supports_full_save", False):
        raise HTTPException(
            status_code=501,
            detail="Full track saving requires a configured server audio provider.",
        )

    return await save_discovery_track(
        track=track,
        username=session.username,
        password=session.password,
        db=db,
        navidrome=navidrome,
        provider=provider,
        music_dir=settings.cadence_music_dir,
        staging_dir=settings.stream_cache_dir,
        star=payload.star,
    )


@router.post("/library/star", response_model=StarTrackResponse)
async def star_track(
    payload: StarTrackRequest,
    request: Request,
    session: UserSession = Depends(require_session),
) -> StarTrackResponse:
    settings = _get_settings(request)
    navidrome = _get_navidrome(request)
    db = _get_db(request)
    provider = _get_provider(request)

    if not payload.track_id.startswith("ext:"):
        await navidrome.star(
            session.username, session.password, payload.track_id, starred=payload.starred
        )
        return StarTrackResponse(
            track_id=payload.track_id,
            starred=payload.starred,
            saved_navidrome_id=payload.track_id,
        )

    track = await db.get_discovery_track(payload.track_id)
    if track is None:
        raise HTTPException(status_code=404, detail="Discovery track not found")

    if track.navidrome_id:
        await navidrome.star(
            session.username, session.password, track.navidrome_id, starred=payload.starred
        )
        return StarTrackResponse(
            track_id=payload.track_id,
            starred=payload.starred,
            saved_navidrome_id=track.navidrome_id,
        )

    if payload.starred and payload.auto_save and getattr(provider, "supports_full_save", False):
        saved = await save_discovery_track(
            track=track,
            username=session.username,
            password=session.password,
            db=db,
            navidrome=navidrome,
            provider=provider,
            music_dir=settings.cadence_music_dir,
            staging_dir=settings.stream_cache_dir,
            star=True,
        )
        return StarTrackResponse(
            track_id=payload.track_id,
            starred=True,
            saved_navidrome_id=saved.navidrome_id,
        )

    return StarTrackResponse(track_id=payload.track_id, starred=payload.starred)


@router.post("/playlists/sync-to-navidrome")
async def sync_mixes_to_navidrome(
    request: Request,
    session: UserSession = Depends(require_session),
) -> dict[str, int]:
    """Sync library-only portions of Cadence mixes so desktop clients (Feishin) see them too."""
    engine = _get_engine(request)
    navidrome = _get_navidrome(request)
    synced = 0
    for mix_id in ("supermix", "replay-mix", "forgotten-favorites"):
        detail = await engine.build_mix(session.username, session.password, mix_id=mix_id)
        ids = [t.navidrome_id for t in detail.tracks if t.navidrome_id]
        if ids:
            await navidrome.sync_playlist(
                session.username,
                session.password,
                f"Cadence · {detail.mix.title}",
                ids,
            )
            synced += 1
    return {"synced_playlists": synced}

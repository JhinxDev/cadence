"""Permanent save-to-Navidrome pipeline with metadata tagging and library scan."""

import asyncio
import contextlib
import os
import re
import shutil
from pathlib import Path

import httpx
from mutagen.flac import FLAC, Picture
from mutagen.id3 import APIC, COMM, TALB, TCON, TDRC, TIT2, TPE1
from mutagen.mp3 import MP3
from mutagen.mp4 import MP4, MP4Cover

from cadence.clients.navidrome import NavidromeClient
from cadence.db import Database
from cadence.models import SaveTrackResponse, TrackDTO
from cadence.providers.base import AudioProvider

INVALID_PATH_CHARS = re.compile(r'[<>:"/\\|?*\x00-\x1f]')


def sanitize_segment(value: str, fallback: str = "Unknown") -> str:
    cleaned = INVALID_PATH_CHARS.sub("_", value.strip()).strip(". ")
    return cleaned[:100] or fallback


def _embed_tags(
    file_path: Path, track: TrackDTO, cover_bytes: bytes | None, cover_mime: str
) -> None:
    ext = file_path.suffix.lower()
    if ext in (".m4a", ".mp4", ".aac"):
        audio = MP4(file_path)
        audio["\xa9nam"] = [track.title]
        audio["\xa9ART"] = [track.artist]
        audio["aART"] = [track.artist]
        audio["\xa9alb"] = [track.album or track.title]
        audio["\xa9cmt"] = ["Cadence Discovery"]
        if track.year:
            audio["\xa9day"] = [str(track.year)]
        if track.genre:
            audio["\xa9gen"] = [track.genre]
        if cover_bytes:
            fmt = MP4Cover.FORMAT_PNG if "png" in cover_mime else MP4Cover.FORMAT_JPEG
            audio["covr"] = [MP4Cover(cover_bytes, imageformat=fmt)]
        audio.save()
    elif ext == ".mp3":
        audio = MP3(file_path)
        if audio.tags is None:
            audio.add_tags()
        audio.tags["TIT2"] = TIT2(encoding=3, text=track.title)
        audio.tags["TPE1"] = TPE1(encoding=3, text=track.artist)
        audio.tags["TALB"] = TALB(encoding=3, text=track.album or track.title)
        audio.tags["COMM::eng"] = COMM(encoding=3, lang="eng", desc="", text="Cadence Discovery")
        if track.year:
            audio.tags["TDRC"] = TDRC(encoding=3, text=str(track.year))
        if track.genre:
            audio.tags["TCON"] = TCON(encoding=3, text=track.genre)
        if cover_bytes:
            audio.tags["APIC:Cover"] = APIC(
                encoding=3, mime=cover_mime, type=3, desc="Cover", data=cover_bytes
            )
        audio.save()
    elif ext == ".flac":
        audio = FLAC(file_path)
        audio["title"] = track.title
        audio["artist"] = track.artist
        audio["albumartist"] = track.artist
        audio["album"] = track.album or track.title
        audio["comment"] = "Cadence Discovery"
        if track.year:
            audio["date"] = str(track.year)
        if track.genre:
            audio["genre"] = track.genre
        if cover_bytes:
            pic = Picture()
            pic.type = 3
            pic.mime = cover_mime
            pic.data = cover_bytes
            audio.clear_pictures()
            audio.add_picture(pic)
        audio.save()


async def _fetch_cover(url: str | None) -> tuple[bytes | None, str]:
    if not url:
        return None, "image/jpeg"
    try:
        async with httpx.AsyncClient(timeout=8.0, follow_redirects=True) as client:
            resp = await client.get(url)
            if resp.status_code == 200 and len(resp.content) > 256:
                mime = resp.headers.get("content-type", "image/jpeg").split(";")[0].strip()
                return resp.content, mime
    except Exception:
        pass
    return None, "image/jpeg"


async def save_discovery_track(
    *,
    track: TrackDTO,
    username: str,
    password: str,
    db: Database,
    navidrome: NavidromeClient,
    provider: AudioProvider,
    music_dir: Path,
    staging_dir: Path,
    star: bool = False,
) -> SaveTrackResponse:
    """Acquire full audio, tag, save under /music/Cadence, scan Navidrome, and optionally star."""
    if track.navidrome_id:
        if star:
            await navidrome.star(username, password, track.navidrome_id, starred=True)
        return SaveTrackResponse(
            status="already_in_library",
            track_id=track.id,
            navidrome_id=track.navidrome_id,
        )

    acquired = await provider.acquire_for_library(track, staging_dir)
    if acquired.file_path is None or not acquired.file_path.exists():
        raise RuntimeError("Provider failed to deliver a local audio file")

    artist_dir = sanitize_segment(track.artist)
    album_dir = sanitize_segment(track.album or track.title)
    title_stem = sanitize_segment(track.title)
    ext = acquired.file_path.suffix or ".m4a"

    dest_dir = music_dir / "Cadence" / artist_dir / album_dir
    dest_dir.mkdir(parents=True, exist_ok=True)
    for parent in (music_dir / "Cadence", music_dir / "Cadence" / artist_dir, dest_dir):
        with contextlib.suppress(OSError):
            os.chmod(parent, 0o755)

    dest_path = dest_dir / f"{title_stem}{ext}"
    tmp_path = dest_dir / f".{title_stem}.tmp{ext}"
    shutil.copy2(acquired.file_path, tmp_path)

    cover_bytes, cover_mime = await _fetch_cover(track.artwork_url)
    with contextlib.suppress(Exception):
        # Keep valid audio even if a container format rejects a specific tag field
        _embed_tags(tmp_path, track, cover_bytes, cover_mime)

    if cover_bytes and not (dest_dir / "cover.jpg").exists():
        cover_path = dest_dir / "cover.jpg"
        cover_path.write_bytes(cover_bytes)
        with contextlib.suppress(OSError):
            os.chmod(cover_path, 0o644)

    tmp_path.replace(dest_path)
    with contextlib.suppress(OSError):
        os.chmod(dest_path, 0o644)

    await navidrome.start_scan(username, password)
    nav_id: str | None = None
    for _ in range(12):
        await asyncio.sleep(0.6)
        scanning = await navidrome.get_scan_status(username, password)
        res = await navidrome.search(
            username,
            password,
            f"{track.artist} {track.title}",
            song_count=8,
            album_count=0,
            artist_count=0,
        )
        songs = res.get("song", [])
        match = next(
            (
                s
                for s in songs
                if track.title.lower() in (s.get("title") or "").lower()
                and track.artist.lower().split(",")[0].strip() in (s.get("artist") or "").lower()
            ),
            None,
        )
        if match:
            nav_id = str(match["id"])
            break
        if not scanning:
            break

    if nav_id:
        await db.mark_discovery_saved(track.id, nav_id)
        if star:
            await navidrome.star(username, password, nav_id, starred=True)

    return SaveTrackResponse(
        status="saved",
        track_id=track.id,
        navidrome_id=nav_id,
        file_path=str(dest_path),
    )

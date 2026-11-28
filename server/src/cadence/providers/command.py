"""Generic external subprocess provider hook for self-hosted deployments."""

import asyncio
import json
from pathlib import Path

from cadence.models import TrackDTO
from cadence.providers.base import ResolvedAudio
from cadence.providers.cache import enforce_cache_limit, touch_cache_file
from cadence.providers.preview import PreviewAudioProvider


class CommandAudioProvider:
    """Invokes an operator-configured script via JSON stdin/stdout for full track resolution."""

    name = "command"
    supports_full_save = True

    def __init__(
        self,
        script_path: str,
        cache_dir: Path,
        max_cache_mb: int = 2048,
    ) -> None:
        self.script_path = Path(script_path)
        self.cache_dir = cache_dir
        self.max_cache_mb = max_cache_mb
        self._fallback = PreviewAudioProvider()
        self._inflight: dict[str, asyncio.Task[ResolvedAudio]] = {}
        self._prefetch_sem = asyncio.Semaphore(3)
        self.cache_dir.mkdir(parents=True, exist_ok=True)

    def is_cached(self, ext_id: str) -> bool:
        return self._cached_candidate(ext_id) is not None

    def _cached_candidate(self, ext_id: str) -> Path | None:
        safe = ext_id.replace(":", "_")
        for ext in ("m4a", "flac", "mp3", "opus", "ogg"):
            cand = self.cache_dir / f"{safe}.{ext}"
            if cand.exists() and cand.stat().st_size > 4096:
                return cand
        return None

    async def _invoke(self, action: str, track: TrackDTO, output_stem: Path) -> ResolvedAudio:
        if not self.script_path.exists():
            raise FileNotFoundError(f"Provider script not found: {self.script_path}")

        payload = json.dumps(
            {
                "action": action,
                "track_id": track.id,
                "artist": track.artist,
                "title": track.title,
                "album": track.album,
                "duration_sec": track.duration_sec,
                "isrc": track.isrc,
                "output_stem": str(output_stem),
            }
        ).encode("utf-8")

        proc = await asyncio.create_subprocess_exec(
            str(self.script_path),
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(payload), timeout=90.0)
        if proc.returncode != 0:
            err = stderr.decode("utf-8", errors="replace").strip()
            raise RuntimeError(f"Provider hook exited {proc.returncode}: {err}")

        data = json.loads(stdout.decode("utf-8"))
        file_path = Path(data["file_path"])
        if not file_path.exists() or file_path.stat().st_size == 0:
            raise RuntimeError(f"Provider returned missing audio file: {file_path}")

        return ResolvedAudio(
            file_path=file_path,
            mime_type=data.get("mime_type", "audio/mp4"),
            is_preview=bool(data.get("is_preview", False)),
            source_label=data.get("source_label", "command"),
        )

    async def _resolve_uncached(self, track: TrackDTO) -> ResolvedAudio:
        safe = track.id.replace(":", "_")
        try:
            resolved = await self._invoke("resolve", track, self.cache_dir / safe)
            enforce_cache_limit(self.cache_dir, self.max_cache_mb)
            return resolved
        except Exception:
            if track.preview_url:
                return await self._fallback.resolve_stream(track)
            raise

    async def resolve_stream(self, track: TrackDTO) -> ResolvedAudio:
        cached = self._cached_candidate(track.id)
        if cached is not None:
            touch_cache_file(cached)
            mime = (
                "audio/flac"
                if cached.suffix == ".flac"
                else ("audio/mpeg" if cached.suffix == ".mp3" else "audio/mp4")
            )
            return ResolvedAudio(
                file_path=cached,
                mime_type=mime,
                is_preview=False,
                source_label="cache",
            )

        existing = self._inflight.get(track.id)
        if existing is not None:
            return await asyncio.shield(existing)

        task = asyncio.create_task(self._resolve_uncached(track))
        self._inflight[track.id] = task
        try:
            return await asyncio.shield(task)
        finally:
            if self._inflight.get(track.id) is task and task.done():
                self._inflight.pop(track.id, None)

    def schedule_prefetch(self, tracks: list[TrackDTO], limit: int = 3) -> int:
        queued = 0
        for track in tracks:
            if queued >= limit:
                break
            if not track.id.startswith("ext:") or track.navidrome_id:
                continue
            if self.is_cached(track.id) or track.id in self._inflight:
                continue

            async def _warm(item: TrackDTO = track) -> ResolvedAudio:
                async with self._prefetch_sem:
                    cached = self._cached_candidate(item.id)
                    if cached is not None:
                        mime = (
                            "audio/flac"
                            if cached.suffix == ".flac"
                            else ("audio/mpeg" if cached.suffix == ".mp3" else "audio/mp4")
                        )
                        return ResolvedAudio(
                            file_path=cached,
                            mime_type=mime,
                            is_preview=False,
                            source_label="cache",
                        )
                    return await self._resolve_uncached(item)

            task = asyncio.create_task(_warm())
            self._inflight[track.id] = task

            def _cleanup(done_task: asyncio.Task[ResolvedAudio], tid: str = track.id) -> None:
                if self._inflight.get(tid) is done_task:
                    self._inflight.pop(tid, None)
                if not done_task.cancelled():
                    _ = done_task.exception()

            task.add_done_callback(_cleanup)
            queued += 1
        return queued

    async def acquire_for_library(self, track: TrackDTO, target_dir: Path) -> ResolvedAudio:
        target_dir.mkdir(parents=True, exist_ok=True)
        cached = self._cached_candidate(track.id)
        if cached is not None:
            mime = (
                "audio/flac"
                if cached.suffix == ".flac"
                else ("audio/mpeg" if cached.suffix == ".mp3" else "audio/mp4")
            )
            return ResolvedAudio(
                file_path=cached,
                mime_type=mime,
                is_preview=False,
                source_label="cache",
            )

        safe = track.id.replace(":", "_")
        return await self._invoke("acquire", track, target_dir / safe)

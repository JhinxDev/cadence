"""Default public-safe preview provider using open catalog 30-second previews."""

from pathlib import Path

from cadence.models import TrackDTO
from cadence.providers.base import ResolvedAudio


class PreviewAudioProvider:
    """Streams legal 30s catalog previews from Deezer/iTunes without local downloads."""

    name = "preview"
    supports_full_save = False

    async def resolve_stream(self, track: TrackDTO) -> ResolvedAudio:
        if not track.preview_url:
            raise ValueError(f"No catalog preview URL available for {track.artist} - {track.title}")
        return ResolvedAudio(
            remote_url=track.preview_url,
            mime_type="audio/mpeg",
            is_preview=True,
            source_label="catalog-preview",
        )

    async def acquire_for_library(self, track: TrackDTO, target_dir: Path) -> ResolvedAudio:
        raise RuntimeError(
            "Saving discovery tracks requires a full-audio server provider hook "
            "(CADENCE_PROVIDER=command)."
        )

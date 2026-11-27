"""Pluggable audio provider protocol and resolution results."""

from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from cadence.models import TrackDTO


@dataclass(frozen=True, slots=True)
class ResolvedAudio:
    """Resolved audio stream or local file ready for HTTP Range streaming or saving."""

    file_path: Path | None = None
    remote_url: str | None = None
    mime_type: str = "audio/mpeg"
    is_preview: bool = True
    source_label: str = "preview"


class AudioProvider(Protocol):
    """Protocol implemented by preview or external command audio providers."""

    name: str
    supports_full_save: bool

    async def resolve_stream(self, track: TrackDTO) -> ResolvedAudio:
        """Resolve an audio stream or cached file for playback."""
        ...

    async def acquire_for_library(self, track: TrackDTO, target_dir: Path) -> ResolvedAudio:
        """Acquire full-length audio ready to be tagged and moved into Navidrome."""
        ...

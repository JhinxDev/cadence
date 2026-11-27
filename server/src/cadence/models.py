"""Pydantic data contracts shared across API endpoints and engines."""

from typing import Literal

from pydantic import BaseModel, Field

RadioMode = Literal["familiar", "balanced", "discover"]
TrackSource = Literal["library", "discovery"]


class CapabilitiesResponse(BaseModel):
    service: str = "cadence"
    version: str = "0.1.0"
    discovery_enabled: bool = True
    full_discovery_streaming: bool = False
    save_to_library_enabled: bool = False
    lyrics_enabled: bool = True
    subsonic_proxy_enabled: bool = True


class LoginRequest(BaseModel):
    username: str = Field(min_length=1)
    password: str = Field(min_length=1)


class LoginResponse(BaseModel):
    token: str
    username: str
    expires_at: int
    capabilities: CapabilitiesResponse


class TrackDTO(BaseModel):
    id: str
    title: str
    artist: str
    album: str = ""
    duration_sec: int = 0
    artwork_url: str | None = None
    source: TrackSource = "library"
    in_library: bool = True
    is_preview: bool = False
    is_starred: bool = False
    reason: str | None = None
    navidrome_id: str | None = None
    year: int | None = None
    genre: str | None = None
    bpm: float | None = None
    preview_url: str | None = None
    deezer_id: str | None = None
    isrc: str | None = None


class SpeedDialItemDTO(BaseModel):
    id: str
    kind: Literal["album", "playlist", "track", "mix"]
    title: str
    subtitle: str
    artwork_url: str | None = None
    target_id: str
    tracks: list[TrackDTO] = Field(default_factory=list)


class MixCardDTO(BaseModel):
    id: str
    title: str
    subtitle: str
    accent_hex: str
    track_count: int
    mood: str | None = None
    artwork_urls: list[str] = Field(default_factory=list)
    badge: str = "MADE FOR YOU"


class AlbumCardDTO(BaseModel):
    id: str
    title: str
    artist: str
    year: int | None = None
    song_count: int = 0
    artwork_url: str | None = None


class ArtistCardDTO(BaseModel):
    id: str
    name: str
    reason: str
    artwork_url: str | None = None
    in_library: bool = False
    seed_artist: str | None = None


class HomeFeedResponse(BaseModel):
    mood: str = "All"
    moods: list[str]
    speed_dial: list[SpeedDialItemDTO]
    quick_picks: list[TrackDTO]
    made_for_you: list[MixCardDTO]
    listen_again: list[AlbumCardDTO]
    recommended_artists: list[ArtistCardDTO]
    new_in_library: list[AlbumCardDTO]


class MixDetailResponse(BaseModel):
    mix: MixCardDTO
    tracks: list[TrackDTO]


class RadioStartRequest(BaseModel):
    seed_track: TrackDTO | None = None
    seed_artist: str | None = None
    mood: str | None = None
    mode: RadioMode = "balanced"
    count: int = Field(default=20, ge=5, le=50)


class RadioNextRequest(BaseModel):
    session_id: str
    mode: RadioMode | None = None
    count: int = Field(default=15, ge=5, le=50)


class RadioResponse(BaseModel):
    session_id: str
    mode: RadioMode
    seed_label: str
    tracks: list[TrackDTO]


class SearchResponse(BaseModel):
    query: str
    library_tracks: list[TrackDTO]
    discovery_tracks: list[TrackDTO]
    library_albums: list[AlbumCardDTO]
    artists: list[ArtistCardDTO]


class LyricsLineDTO(BaseModel):
    time_ms: int | None = None
    text: str


class LyricsResponse(BaseModel):
    title: str
    artist: str
    synced: bool = False
    source: str = "none"
    lines: list[LyricsLineDTO] = Field(default_factory=list)
    plain_text: str | None = None


class SaveTrackRequest(BaseModel):
    track_id: str
    star: bool = False


class SaveTrackResponse(BaseModel):
    status: Literal["saved", "already_in_library"]
    track_id: str
    navidrome_id: str | None = None
    file_path: str | None = None


class StarTrackRequest(BaseModel):
    track_id: str
    starred: bool = True
    auto_save: bool = False


class StarTrackResponse(BaseModel):
    track_id: str
    starred: bool
    saved_navidrome_id: str | None = None

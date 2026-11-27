"""Runtime configuration for Cadence Discovery Companion."""

from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Typed environment settings for the Cadence server."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    navidrome_url: str = Field(default="http://navidrome:4533", alias="NAVIDROME_URL")
    cadence_data_dir: Path = Field(default=Path("/data"), alias="CADENCE_DATA_DIR")
    cadence_music_dir: Path = Field(default=Path("/music"), alias="CADENCE_MUSIC_DIR")
    cadence_secret_key: str = Field(
        default="dev-insecure-change-me-in-production",
        alias="CADENCE_SECRET_KEY",
    )
    cadence_provider: str = Field(default="preview", alias="CADENCE_PROVIDER")
    cadence_provider_script: str = Field(default="", alias="CADENCE_PROVIDER_SCRIPT")
    cadence_slskd_url: str = Field(default="", alias="CADENCE_SLSKD_URL")
    cadence_slskd_api_key: str = Field(default="", alias="CADENCE_SLSKD_API_KEY")
    cadence_cache_max_mb: int = Field(default=2048, alias="CADENCE_CACHE_MAX_MB")
    cadence_sync_playlists: bool = Field(default=True, alias="CADENCE_SYNC_PLAYLISTS")
    session_ttl_seconds: int = Field(default=60 * 60 * 24 * 30, alias="CADENCE_SESSION_TTL")

    @property
    def db_path(self) -> Path:
        return self.cadence_data_dir / "cadence.db"

    @property
    def stream_cache_dir(self) -> Path:
        return self.cadence_data_dir / "cache" / "streams"

    @property
    def artwork_cache_dir(self) -> Path:
        return self.cadence_data_dir / "cache" / "artwork"


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return cached runtime settings."""
    return Settings()

"""FastAPI application entrypoint for Cadence Discovery Companion."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI

from cadence import __version__
from cadence.api.subsonic_proxy import router as subsonic_router
from cadence.api.v1 import router as v1_router
from cadence.clients.catalog import ExternalCatalogClient
from cadence.clients.navidrome import NavidromeClient
from cadence.config import Settings, get_settings
from cadence.db import Database
from cadence.engine.mixes import DiscoveryEngine
from cadence.providers.base import AudioProvider
from cadence.providers.command import CommandAudioProvider
from cadence.providers.preview import PreviewAudioProvider


def _build_provider(settings: Settings) -> AudioProvider:
    if settings.cadence_provider.lower() == "command" and settings.cadence_provider_script:
        return CommandAudioProvider(
            script_path=settings.cadence_provider_script,
            cache_dir=settings.stream_cache_dir,
            max_cache_mb=settings.cadence_cache_max_mb,
        )
    return PreviewAudioProvider()


def create_app(settings: Settings | None = None) -> FastAPI:
    cfg = settings or get_settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        db = Database(cfg.db_path)
        await db.connect()
        http_client = httpx.AsyncClient(timeout=12.0)
        navidrome = NavidromeClient(cfg.navidrome_url, http_client=http_client)
        catalog = ExternalCatalogClient(db=db, http_client=http_client)
        engine = DiscoveryEngine(db=db, navidrome=navidrome, catalog=catalog)
        provider = _build_provider(cfg)

        app.state.settings = cfg
        app.state.db = db
        app.state.http_client = http_client
        app.state.navidrome = navidrome
        app.state.catalog = catalog
        app.state.engine = engine
        app.state.provider = provider
        try:
            yield
        finally:
            await http_client.aclose()
            await db.close()

    app = FastAPI(
        title="Cadence Discovery Companion",
        version=__version__,
        lifespan=lifespan,
    )
    app.include_router(v1_router)
    app.include_router(subsonic_router)

    @app.get("/health")
    async def health() -> dict[str, object]:
        nav_ok = await app.state.navidrome.server_reachable()
        return {
            "status": "ok",
            "service": "cadence",
            "version": __version__,
            "provider": cfg.cadence_provider,
            "navidrome_reachable": nav_ok,
        }

    return app


app = create_app()

"""YouTube Music-style Home, Mixes, and Infinite Radio engine."""

import asyncio
import random
import secrets
from typing import Any

from cadence.clients.catalog import ExternalCatalogClient, normalize_key
from cadence.clients.navidrome import NavidromeClient
from cadence.db import Database
from cadence.engine.taste import TasteProfile, build_taste_profile
from cadence.models import (
    ArtistCardDTO,
    HomeFeedResponse,
    MixCardDTO,
    MixDetailResponse,
    RadioMode,
    RadioResponse,
    TrackDTO,
)

MOOD_LABELS = ["All", "Energize", "Chill", "Focus", "Workout", "Late Night", "Discover"]

MOOD_KEYWORDS: dict[str, tuple[str, ...]] = {
    "Energize": ("rap", "hip", "trap", "drill", "pop", "dance", "electro"),
    "Chill": ("lofi", "lo-fi", "chill", "r&b", "soul", "acoustic", "jazz"),
    "Focus": ("instrumental", "lofi", "ambient", "soundtrack", "classical", "piano"),
    "Workout": ("rap", "hip-hop", "rock", "metal", "electronic", "phunk"),
    "Late Night": ("r&b", "night", "dark", "cloud", "synth", "chill"),
    "Discover": (),
}

MIX_CATALOG: dict[str, dict[str, str]] = {
    "supermix": {
        "title": "My Supermix",
        "subtitle": "Your heavy rotation blended with fresh finds",
        "accent": "#FF3B5C",
        "badge": "PERSONALIZED",
    },
    "discover-mix": {
        "title": "Discover Mix",
        "subtitle": "New artists & tracks tailored to your taste",
        "accent": "#7C5CFF",
        "badge": "NEW MUSIC",
    },
    "replay-mix": {
        "title": "Replay Mix",
        "subtitle": "The songs and albums you keep coming back to",
        "accent": "#F59E0B",
        "badge": "ON REPEAT",
    },
    "new-releases": {
        "title": "New Release Mix",
        "subtitle": "Recent drops from artists in your orbit",
        "accent": "#EC4899",
        "badge": "FRESH DROPS",
    },
    "forgotten-favorites": {
        "title": "Forgotten Favorites",
        "subtitle": "Starred tracks ready for a comeback",
        "accent": "#14B8A6",
        "badge": "REDISCOVER",
    },
}


def _dedupe_tracks(
    tracks: list[TrackDTO],
    exclude_keys: set[str] | None = None,
    library_keys: set[str] | None = None,
) -> list[TrackDTO]:
    seen: set[str] = set(exclude_keys or set())
    out: list[TrackDTO] = []
    for t in tracks:
        key = normalize_key(t.artist, t.title)
        if not key or key in seen:
            continue
        seen.add(key)
        if library_keys and t.source == "discovery" and key in library_keys:
            # Skip external duplicates already owned in Navidrome
            continue
        out.append(t)
    return out


def _matches_mood(track: TrackDTO, mood: str) -> bool:
    if mood in ("All", "Discover"):
        return True
    keywords = MOOD_KEYWORDS.get(mood, ())
    if not keywords:
        return True
    haystack = f"{track.genre or ''} {track.album} {track.title}".lower()
    if any(kw in haystack for kw in keywords):
        return True
    if mood in ("Energize", "Workout") and track.bpm and track.bpm >= 112:
        return True
    return bool(mood in ("Chill", "Focus", "Late Night") and track.bpm and track.bpm <= 105)


class DiscoveryEngine:
    """Orchestrates Home feed, editorial mixes, and endless multi-mode radio."""

    def __init__(
        self,
        db: Database,
        navidrome: NavidromeClient,
        catalog: ExternalCatalogClient,
    ) -> None:
        self.db = db
        self.navidrome = navidrome
        self.catalog = catalog

    async def _discover_for_artists(
        self,
        profile: TasteProfile,
        limit_artists: int = 4,
    ) -> tuple[list[TrackDTO], list[ArtistCardDTO]]:
        seed_artists = profile.top_artists[:limit_artists]
        if not seed_artists:
            return [], []

        related_tasks = [self.catalog.get_related_artists(name, limit=5) for name in seed_artists]
        top_tasks = [
            self.catalog.get_artist_top_tracks(
                name, limit=4, reason=f"Because you listen to {name}"
            )
            for name in seed_artists
        ]
        related_lists, top_lists = await asyncio.gather(
            asyncio.gather(*related_tasks, return_exceptions=True),
            asyncio.gather(*top_tasks, return_exceptions=True),
        )

        rec_artists: list[ArtistCardDTO] = []
        seen_artists: set[str] = set()
        for result in related_lists:
            if isinstance(result, BaseException):
                continue
            for card in result:
                low = card.name.strip().lower()
                if low in seen_artists:
                    continue
                seen_artists.add(low)
                card.in_library = low in profile.library_artists_lower
                if not card.in_library:
                    rec_artists.append(card)

        discovery_tracks: list[TrackDTO] = []
        for result in top_lists:
            if isinstance(result, BaseException):
                continue
            discovery_tracks.extend(result)

        # Also pull top tracks from top 4 recommended new artists
        new_artist_tasks = [
            self.catalog.get_artist_top_tracks(artist.name, limit=4, reason=artist.reason)
            for artist in rec_artists[:4]
        ]
        if new_artist_tasks:
            new_tracks_lists = await asyncio.gather(*new_artist_tasks, return_exceptions=True)
            for result in new_tracks_lists:
                if isinstance(result, BaseException):
                    continue
                discovery_tracks.extend(result)

        filtered = _dedupe_tracks(discovery_tracks, library_keys=profile.library_keys)
        await self.db.upsert_discovery_tracks(filtered)
        return filtered, rec_artists[:10]

    async def build_home(
        self,
        username: str,
        password: str,
        mood: str = "All",
    ) -> HomeFeedResponse:
        active_mood = mood if mood in MOOD_LABELS else "All"
        profile = await build_taste_profile(self.navidrome, username, password)
        discovery_tracks, rec_artists = await self._discover_for_artists(profile, limit_artists=4)

        lib_pool = _dedupe_tracks(
            profile.starred_tracks + profile.frequent_tracks + profile.random_pool
        )
        if active_mood not in ("All", "Discover"):
            mood_lib = [t for t in lib_pool if _matches_mood(t, active_mood)]
            mood_disc = [t for t in discovery_tracks if _matches_mood(t, active_mood)]
            if len(mood_lib) >= 4:
                lib_pool = mood_lib
            if len(mood_disc) >= 4:
                discovery_tracks = mood_disc

        # Quick Picks: interleave library favorites + fresh discovery tracks (16 items for 4x4 grid)
        quick_picks: list[TrackDTO] = []
        if active_mood == "Discover":
            quick_picks = discovery_tracks[:16]
            if len(quick_picks) < 12:
                quick_picks.extend(lib_pool[: 16 - len(quick_picks)])
        else:
            lib_sample = lib_pool[:10]
            disc_sample = discovery_tracks[:8]
            for i in range(max(len(lib_sample), len(disc_sample))):
                if i < len(lib_sample):
                    quick_picks.append(lib_sample[i])
                if i < len(disc_sample):
                    quick_picks.append(disc_sample[i])
            quick_picks = quick_picks[:16]

        def collage_from(tracks: list[TrackDTO], fallback: list[str]) -> list[str]:
            urls = [t.artwork_url for t in tracks if t.artwork_url]
            deduped = list(dict.fromkeys(urls))
            if len(deduped) < 4:
                for fb in fallback:
                    if fb not in deduped:
                        deduped.append(fb)
            return deduped[:4]

        fallback_arts = [
            a.artwork_url for a in profile.recent_albums + profile.newest_albums if a.artwork_url
        ]

        made_for_you: list[MixCardDTO] = []
        for mix_id, meta in MIX_CATALOG.items():
            if mix_id == "discover-mix":
                arts = collage_from(discovery_tracks, fallback_arts)
                count = max(len(discovery_tracks), 20)
            elif mix_id == "replay-mix":
                arts = collage_from(profile.frequent_tracks + profile.starred_tracks, fallback_arts)
                count = min(max(len(profile.frequent_tracks), 15), 25)
            elif mix_id == "new-releases":
                arts = collage_from(discovery_tracks[::-1], fallback_arts)
                count = 20
            elif mix_id == "forgotten-favorites":
                arts = collage_from(profile.starred_tracks[::-1], fallback_arts)
                count = min(max(len(profile.starred_tracks), 15), 25)
            else:
                arts = collage_from(quick_picks, fallback_arts)
                count = 25

            made_for_you.append(
                MixCardDTO(
                    id=mix_id,
                    title=meta["title"],
                    subtitle=meta["subtitle"],
                    accent_hex=meta["accent"],
                    track_count=count,
                    mood=active_mood if active_mood != "All" else None,
                    artwork_urls=arts,
                    badge=meta["badge"],
                )
            )

        return HomeFeedResponse(
            mood=active_mood,
            moods=MOOD_LABELS,
            speed_dial=profile.speed_dial,
            quick_picks=quick_picks,
            made_for_you=made_for_you,
            listen_again=profile.recent_albums[:10],
            recommended_artists=rec_artists,
            new_in_library=profile.newest_albums[:10],
        )

    async def build_mix(
        self,
        username: str,
        password: str,
        mix_id: str,
        mood: str = "All",
    ) -> MixDetailResponse:
        meta = MIX_CATALOG.get(mix_id, MIX_CATALOG["supermix"])
        profile = await build_taste_profile(self.navidrome, username, password)

        tracks: list[TrackDTO] = []
        if mix_id == "discover-mix":
            disc, _ = await self._discover_for_artists(profile, limit_artists=6)
            tracks = disc[:30]
        elif mix_id == "new-releases":
            tasks = [
                self.catalog.get_artist_latest_tracks(name, limit=4)
                for name in profile.top_artists[:6]
            ]
            results = await asyncio.gather(*tasks, return_exceptions=True)
            raw: list[TrackDTO] = []
            for r in results:
                if not isinstance(r, BaseException):
                    raw.extend(r)
            tracks = _dedupe_tracks(raw, library_keys=profile.library_keys)[:30]
            await self.db.upsert_discovery_tracks(tracks)
        elif mix_id == "replay-mix":
            tracks = _dedupe_tracks(profile.frequent_tracks + profile.starred_tracks)[:25]
        elif mix_id == "forgotten-favorites":
            pool = list(profile.starred_tracks)
            random.shuffle(pool)
            tracks = _dedupe_tracks(pool)[:25]
        else:  # supermix
            disc, _ = await self._discover_for_artists(profile, limit_artists=5)
            lib = _dedupe_tracks(
                profile.starred_tracks + profile.frequent_tracks + profile.random_pool
            )
            for i in range(max(len(lib), len(disc))):
                if i < len(lib):
                    tracks.append(lib[i])
                if i < len(disc):
                    tracks.append(disc[i])
            tracks = _dedupe_tracks(tracks)[:30]

        if mood not in ("All", "Discover"):
            mood_filtered = [t for t in tracks if _matches_mood(t, mood)]
            if len(mood_filtered) >= 6:
                tracks = mood_filtered

        arts = list(dict.fromkeys([t.artwork_url for t in tracks if t.artwork_url]))[:4]
        card = MixCardDTO(
            id=mix_id,
            title=meta["title"],
            subtitle=meta["subtitle"],
            accent_hex=meta["accent"],
            track_count=len(tracks),
            mood=mood if mood != "All" else None,
            artwork_urls=arts,
            badge=meta["badge"],
        )
        return MixDetailResponse(mix=card, tracks=tracks)

    async def start_radio(
        self,
        username: str,
        password: str,
        seed_track: TrackDTO | None,
        seed_artist: str | None,
        mood: str | None,
        mode: RadioMode,
        count: int,
    ) -> RadioResponse:
        session_id = secrets.token_urlsafe(16)
        seed_dict: dict[str, Any] = {
            "seed_track": seed_track.model_dump() if seed_track else None,
            "seed_artist": seed_artist,
            "mood": mood,
        }
        seed_label = (
            f"{seed_track.title} Radio"
            if seed_track
            else (f"{seed_artist} Radio" if seed_artist else f"{mood or 'Personal'} Radio")
        )
        tracks = await self._generate_radio_batch(
            username=username,
            password=password,
            seed=seed_dict,
            mode=mode,
            exclude_keys=set(),
            count=count,
        )
        served_keys = [normalize_key(t.artist, t.title) for t in tracks]
        await self.db.save_radio_session(session_id, username, seed_dict, mode, served_keys)
        return RadioResponse(
            session_id=session_id,
            mode=mode,
            seed_label=seed_label,
            tracks=tracks,
        )

    async def next_radio(
        self,
        username: str,
        password: str,
        session_id: str,
        mode_override: RadioMode | None,
        count: int,
    ) -> RadioResponse:
        session = await self.db.get_radio_session(session_id, username)
        if session is None:
            return await self.start_radio(
                username=username,
                password=password,
                seed_track=None,
                seed_artist=None,
                mood=None,
                mode=mode_override or "balanced",
                count=count,
            )
        mode: RadioMode = mode_override or session["mode"]
        seed = session["seed"]
        exclude_keys = set(session["served_keys"])
        tracks = await self._generate_radio_batch(
            username=username,
            password=password,
            seed=seed,
            mode=mode,
            exclude_keys=exclude_keys,
            count=count,
        )
        new_keys = session["served_keys"] + [normalize_key(t.artist, t.title) for t in tracks]
        await self.db.save_radio_session(session_id, username, seed, mode, new_keys)
        seed_track = seed.get("seed_track")
        seed_label = (
            f"{seed_track['title']} Radio"
            if seed_track
            else (
                f"{seed.get('seed_artist')} Radio" if seed.get("seed_artist") else "Personal Radio"
            )
        )
        return RadioResponse(
            session_id=session_id,
            mode=mode,
            seed_label=seed_label,
            tracks=tracks,
        )

    async def _generate_radio_batch(
        self,
        username: str,
        password: str,
        seed: dict[str, Any],
        mode: RadioMode,
        exclude_keys: set[str],
        count: int,
    ) -> list[TrackDTO]:
        profile = await build_taste_profile(self.navidrome, username, password)
        seed_track_raw = seed.get("seed_track")
        seed_artist = seed.get("seed_artist") or (
            seed_track_raw.get("artist") if seed_track_raw else None
        )
        seed_title = seed_track_raw.get("title") if seed_track_raw else None
        seed_nav_id = (
            seed_track_raw.get("navidrome_id") or seed_track_raw.get("id")
            if seed_track_raw and seed_track_raw.get("source") == "library"
            else None
        )

        # Exclude the seed itself on first page
        local_exclude = set(exclude_keys)
        if seed_artist and seed_title:
            local_exclude.add(normalize_key(seed_artist, seed_title))

        # 1. Library candidates (Maestro getSimilarSongs2 + random library songs)
        lib_candidates: list[TrackDTO] = []
        if seed_nav_id:
            maestro_songs = await self.navidrome.get_similar_songs2(
                username, password, str(seed_nav_id), count=25
            )
            lib_candidates.extend(
                [
                    self.navidrome.song_to_dto(s, reason="Similar sound via Maestro")
                    for s in maestro_songs
                ]
            )
        lib_candidates.extend(profile.starred_tracks + profile.random_pool)
        lib_candidates = _dedupe_tracks(lib_candidates, exclude_keys=local_exclude)

        # 2. Discovery candidates (Deezer track radio + related artists)
        disc_raw: list[TrackDTO] = []
        tasks = []
        if seed_artist and seed_title:
            tasks.append(
                self.catalog.get_track_radio(
                    seed_artist, seed_title, limit=20, reason=f"Radio from {seed_title}"
                )
            )
        if seed_artist:
            tasks.append(
                self.catalog.get_artist_top_tracks(
                    seed_artist, limit=8, reason=f"More from {seed_artist}"
                )
            )
            related = await self.catalog.get_related_artists(seed_artist, limit=4)
            for rel in related[:3]:
                tasks.append(
                    self.catalog.get_artist_top_tracks(
                        rel.name, limit=5, reason=f"Similar to {seed_artist}"
                    )
                )
        elif profile.top_artists:
            for artist in profile.top_artists[:4]:
                tasks.append(
                    self.catalog.get_artist_top_tracks(
                        artist, limit=5, reason=f"Because you listen to {artist}"
                    )
                )

        if tasks:
            results = await asyncio.gather(*tasks, return_exceptions=True)
            for r in results:
                if not isinstance(r, BaseException):
                    disc_raw.extend(r)

        disc_candidates = _dedupe_tracks(
            disc_raw, exclude_keys=local_exclude, library_keys=profile.library_keys
        )
        await self.db.upsert_discovery_tracks(disc_candidates)

        # Mix ratio by mode
        ratio_map: dict[RadioMode, float] = {
            "familiar": 0.75,
            "balanced": 0.45,
            "discover": 0.15,
        }
        lib_ratio = ratio_map[mode]
        target_lib = int(round(count * lib_ratio))
        target_disc = count - target_lib

        chosen_lib = lib_candidates[:target_lib]
        chosen_disc = disc_candidates[:target_disc]

        # Backfill if either side came up short
        if len(chosen_disc) < target_disc:
            chosen_lib.extend(
                lib_candidates[target_lib : target_lib + (target_disc - len(chosen_disc))]
            )
        if len(chosen_lib) < target_lib:
            chosen_disc.extend(
                disc_candidates[target_disc : target_disc + (target_lib - len(chosen_lib))]
            )

        blended: list[TrackDTO] = []
        for i in range(max(len(chosen_lib), len(chosen_disc))):
            if i < len(chosen_lib):
                blended.append(chosen_lib[i])
            if i < len(chosen_disc):
                blended.append(chosen_disc[i])
        return blended[:count]

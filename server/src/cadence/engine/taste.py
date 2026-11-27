"""Builds a weighted listener taste profile from Navidrome library & playback history."""

import asyncio
from collections import Counter
from dataclasses import dataclass, field
from typing import Any

from cadence.clients.catalog import normalize_key
from cadence.clients.navidrome import NavidromeClient
from cadence.models import AlbumCardDTO, SpeedDialItemDTO, TrackDTO


@dataclass
class TasteProfile:
    top_artists: list[str] = field(default_factory=list)
    top_genres: list[str] = field(default_factory=list)
    library_keys: set[str] = field(default_factory=set)
    library_artists_lower: set[str] = field(default_factory=set)
    starred_tracks: list[TrackDTO] = field(default_factory=list)
    frequent_tracks: list[TrackDTO] = field(default_factory=list)
    recent_albums: list[AlbumCardDTO] = field(default_factory=list)
    newest_albums: list[AlbumCardDTO] = field(default_factory=list)
    frequent_albums: list[AlbumCardDTO] = field(default_factory=list)
    playlists: list[dict[str, Any]] = field(default_factory=list)
    speed_dial: list[SpeedDialItemDTO] = field(default_factory=list)
    random_pool: list[TrackDTO] = field(default_factory=list)


async def build_taste_profile(
    navidrome: NavidromeClient,
    username: str,
    password: str,
) -> TasteProfile:
    """Aggregate Navidrome signals into a TasteProfile with bounded concurrency."""
    starred_task = navidrome.get_starred(username, password)
    recent_task = navidrome.get_album_list(username, password, "recent", size=14)
    frequent_task = navidrome.get_album_list(username, password, "frequent", size=14)
    newest_task = navidrome.get_album_list(username, password, "newest", size=14)
    playlists_task = navidrome.get_playlists(username, password)
    random_task = navidrome.get_random_songs(username, password, size=60)

    starred, recent_albs, freq_albs, newest_albs, playlists, random_songs = await asyncio.gather(
        starred_task,
        recent_task,
        frequent_task,
        newest_task,
        playlists_task,
        random_task,
    )

    artist_scores: Counter[str] = Counter()
    genre_scores: Counter[str] = Counter()
    library_keys: set[str] = set()
    library_artists_lower: set[str] = set()

    starred_songs = [
        navidrome.song_to_dto(s, reason="From your Liked songs") for s in starred.get("song", [])
    ]
    random_pool = [navidrome.song_to_dto(s) for s in random_songs]

    for track in starred_songs:
        library_keys.add(normalize_key(track.artist, track.title))
        library_artists_lower.add(track.artist.strip().lower())
        artist_scores[track.artist] += 4
        if track.genre:
            genre_scores[track.genre] += 3

    for track in random_pool:
        library_keys.add(normalize_key(track.artist, track.title))
        library_artists_lower.add(track.artist.strip().lower())
        artist_scores[track.artist] += 1
        if track.genre:
            genre_scores[track.genre] += 1

    # Pull songs from top frequent albums to seed heavy-rotation tracks
    frequent_tracks: list[TrackDTO] = []
    freq_detail_tasks = [
        navidrome.get_album(username, password, str(alb["id"])) for alb in freq_albs[:5]
    ]
    freq_details = await asyncio.gather(*freq_detail_tasks, return_exceptions=True)
    for alb_data in freq_details:
        if isinstance(alb_data, BaseException):
            continue
        for song in alb_data.get("song", []):
            dto = navidrome.song_to_dto(song, reason="Heavy rotation")
            frequent_tracks.append(dto)
            library_keys.add(normalize_key(dto.artist, dto.title))
            library_artists_lower.add(dto.artist.strip().lower())
            artist_scores[dto.artist] += 3
            if dto.genre:
                genre_scores[dto.genre] += 2

    recent_cards = [navidrome.album_to_dto(a) for a in recent_albs]
    newest_cards = [navidrome.album_to_dto(a) for a in newest_albs]
    freq_cards = [navidrome.album_to_dto(a) for a in freq_albs]

    for card in recent_cards + freq_cards:
        if card.artist:
            artist_scores[card.artist] += 2
            library_artists_lower.add(card.artist.strip().lower())

    speed_dial: list[SpeedDialItemDTO] = []
    seen_dial: set[str] = set()
    for card in (recent_cards + freq_cards + newest_cards)[:12]:
        key = f"album:{card.id}"
        if key in seen_dial:
            continue
        seen_dial.add(key)
        speed_dial.append(
            SpeedDialItemDTO(
                id=key,
                kind="album",
                title=card.title,
                subtitle=card.artist,
                artwork_url=card.artwork_url,
                target_id=card.id,
            )
        )
        if len(speed_dial) >= 9:
            break

    if len(speed_dial) < 9:
        for pl in playlists:
            pid = str(pl.get("id", ""))
            key = f"playlist:{pid}"
            if not pid or key in seen_dial:
                continue
            seen_dial.add(key)
            cover = pl.get("coverArt") or pid
            speed_dial.append(
                SpeedDialItemDTO(
                    id=key,
                    kind="playlist",
                    title=pl.get("name") or "Playlist",
                    subtitle=f"{int(pl.get('songCount') or 0)} songs",
                    artwork_url=f"/api/v1/artwork/{cover}",
                    target_id=pid,
                )
            )
            if len(speed_dial) >= 9:
                break

    return TasteProfile(
        top_artists=[name for name, _ in artist_scores.most_common(12)],
        top_genres=[g for g, _ in genre_scores.most_common(8)],
        library_keys=library_keys,
        library_artists_lower=library_artists_lower,
        starred_tracks=starred_songs,
        frequent_tracks=frequent_tracks,
        recent_albums=recent_cards,
        newest_albums=newest_cards,
        frequent_albums=freq_cards,
        playlists=playlists,
        speed_dial=speed_dial,
        random_pool=random_pool,
    )

# Changelog

All notable changes to Cadence will be documented in this file.

## [0.1.1] - 2026-11-28

### Fixed & Improved
- Fixed `/rest/*` OpenSubsonic proxy header forwarding (`subsonic_proxy.py`) stripping mismatched `content-encoding` / `content-length` headers after `httpx` decompression so `Library` playlists, albums, artists, and liked tracks load reliably on iOS.
- Added fast live search suggestions (`GET /api/v1/search/suggest`) and instant typeahead dropdown results in `SearchView` while keeping Starter Vibes dynamically seeded from the user's library.
- Removed truncated mix overlay badges (`PERSONALIZED` / `NEW`) from `MixCollageArtwork` so mix cards display clean 2x2 collage art with full titles underneath.
- Enforced uniform 1:1 square poster framing across `ArtworkView` and `MixCollageArtwork` (center-cropping 16:9 music video thumbnails cleanly).
- Hardened `AudioPlaybackController` for long background sessions with KVO playback-state syncing, `mediaServicesWereReset` recovery, background tasks during track transitions/radio fetches, and throttled Lock Screen / AirPods `MPNowPlayingInfoCenter` updates.
- Refined the Cadence app icon (`AppIcon-1024.png`) to a cleaner minimalist matte obsidian harmonic mark.

## [0.1.0] - 2026-11-27

### Added
- Clean-room MIT SwiftUI iOS client (`Cadence` + `CadenceCore`) with Dark Obsidian design system (`DESIGN.md`), mood-filtered Home, Speed Dial, 4-row Quick Picks, Made For You mixes, Infinite Radio (Familiar / Balanced / Discover), Search, Library, Now Playing (Up Next, Synced Lyrics, Related), Offline caching, AirPods/Lock Screen remote controls, and CarPlay scene support.
- Self-hosted Python/FastAPI Discovery Companion (`server/`) combining Navidrome/OpenSubsonic, Maestro audio similarity, Deezer/ListenBrainz/iTunes metadata, LRCLIB synced lyrics, HTTP Range streaming, and one-tap save-to-Navidrome.
- GitHub Actions CI for Python lint/tests, Docker build, macOS iOS Simulator UI verification, and TestFlight deployment.

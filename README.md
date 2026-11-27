# Cadence

A clean-room, MIT-licensed **Navidrome / OpenSubsonic** music player for iOS paired with an optional self-hosted **Discovery Companion** server that brings YouTube Music-style personalized mixes, mood filters, infinite radio, lyrics, and instant stream-then-save discovery to your own library.

## Features

- **Personalized Home Feed:** Mood pills (`All`, `Energize`, `Chill`, `Focus`, `Workout`, `Late Night`, `Discover`), 3×3 **Speed Dial**, 4-row **Quick Picks** radio starters, **Mixed For You** (*My Supermix*, *Discover Mix*, *Replay Mix*, *New Release Mix*, *Forgotten Favorites*), **Listen Again**, and **Discover New Artists**.
- **Infinite Radio & Mix Modes:** Start a mix from any song, artist, or mood and steer it live between **Familiar**, **Balanced**, and **Discover** without repeating tracks.
- **Instant Stream-Then-Save:** Stream recommended tracks outside your library and tap **Save to Library** (or turn on auto-save on Like) so your favorite discoveries become permanent tracks in Navidrome.
- **Synced Lyrics & Related:** Pulls Navidrome lyrics first with automatic LRCLIB synced `.lrc` fallback, plus Maestro-backed similar songs and related artists.
- **Reliable iOS Audio Engine:** Built on `AVPlayer`, `AVAudioSession`, `MPNowPlayingInfoCenter`, and `MPRemoteCommandCenter` with interruption and AirPods route-change recovery, AirPlay routing, CarPlay template support, and offline track caching.
- **Works With Any Navidrome / OpenSubsonic Server:** Connects directly to any standard OpenSubsonic server in standalone mode, and unlocks full external discovery when pointed at the Cadence Discovery Companion.

## Repository Layout

- `server/` — Python 3.12 / FastAPI Discovery Companion & transparent `/rest/*` OpenSubsonic proxy.
- `ios/CadenceCore/` — Cross-platform SwiftPM networking, queue, cache, and playback engine with unit tests.
- `ios/Cadence/` — Native SwiftUI iOS 17+ app (`XcodeGen` spec at `ios/project.yml`).
- `ios/CadenceUITests/` — Automated XCUITest flow & screenshot qualification.
- `scripts/` — iOS Simulator qualification and TestFlight release scripts.

## Quick Start (Discovery Companion)

```bash
cp .env.example .env
# Edit NAVIDROME_URL and CADENCE_SECRET_KEY
docker compose up -d --build
```

Check health:

```bash
curl -fsS http://localhost:4545/health
```

## License

MIT — see [LICENSE](LICENSE).

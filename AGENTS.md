# Cadence — Repository Agent Instructions

## Overview

Cadence is a clean-room MIT-licensed music streaming client for iOS (`ios/`) paired with an optional self-hosted Discovery Companion backend (`server/`) for Navidrome / OpenSubsonic servers.

## Stack

- **Discovery Companion (`server/`):** Python 3.12+, FastAPI, Uvicorn, `httpx`, `aiosqlite`, `mutagen`, `pydantic-settings`, managed with `uv` (`ruff` + `pytest`).
- **iOS Core (`ios/CadenceCore/`):** Swift 6 / SwiftPM library with `OpenSubsonicClient`, `CadenceAPIClient`, `QueueEngine`, `OfflineCacheManager`, `KeychainStore`, and `AudioPlaybackController`.
- **iOS App (`ios/Cadence/`):** Native SwiftUI (iOS 17.0+, `dev.jhinx.cadence`), `XcodeGen` (`ios/project.yml`), and XCUITest screenshot qualification (`ios/CadenceUITests/`).

## Commands

- **Server lint & tests:**
  ```bash
  cd server
  uv run ruff check src tests
  uv run ruff format --check src tests
  uv run pytest -v
  ```
- **iOS Simulator qualification (macOS):**
  ```bash
  bash scripts/qualify-ios.sh /tmp/cadence-ios-evidence
  ```

## App Store & Licensing Guardrails (Mandatory)

1. **MIT Clean-Room Code Only:** Never copy or port GPL-3.0 code from `BLeeEZ/amperfy` or other GPL apps into this repository.
2. **App Store Safe Client (`ios/`):** Never include `yt-dlp`, YouTube scraping, torrenting, or unauthorized media downloaders inside `ios/`. The iOS app speaks strictly OpenSubsonic (`/rest/*`) and Cadence Companion REST (`/api/v1/*`) APIs.
3. **Clean Public Server Default:** `server/` defaults to `CADENCE_PROVIDER=preview` (legal 30-second catalog previews from open music APIs + Navidrome/Maestro similarity). Homelab-specific `command` provider scripts remain outside this repo on the operator's server.
4. **UI & Accessibility:** Follow `DESIGN.md` tokens, SwiftUI `@Observable` / `@State` hygiene, `.scrollIndicators(.hidden)`, reduced-motion fallbacks, and VoiceOver labels.

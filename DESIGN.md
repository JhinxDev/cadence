# Cadence Design System (`DESIGN.md`)

Aesthetic direction: **YouTube Music × Apple Music Dark Obsidian**. Built for low-glare late-night listening, vivid album-art ambient lighting, effortless one-handed discovery, and zero clutter.

## Color Tokens

| Token | Hex / Value | Usage |
| --- | --- | --- |
| `canvasBase` | `#08080C` | Primary OLED obsidian background |
| `surfaceElevated` | `#12121B` | Cards, mix tiles, queue sheets, search containers |
| `surfaceGlass` | `#1B1B27` (at `0.78` opacity + `.ultraThinMaterial`) | Floating mini-player, mood pills, control capsules |
| `surfaceStroke` | `#FFFFFF` at `0.08` opacity | Hairline 1pt borders on glass cards and pills |
| `inkPrimary` | `#F7F7FA` | Headlines, track titles, primary actions |
| `inkSecondary` | `#9B9BA8` | Artist names, subtitles, metadata |
| `inkMuted` | `#666675` | Timestamps, section kickers, inactive tab icons |
| `accentPrimary` | `#FF3B5C` | Active play highlights, save CTA, progress scrubbers, liked heart |
| `accentDiscovery` | `#7C5CFF` | `NEW` discovery badges, radio tuner accents |
| `accentSuccess` | `#2BD984` | `Saved` / `In Library` confirmations, offline ready badge |
| `ambientGlow` | Dynamic artwork tint / mood tint at `0.28` alpha radial blur | Soft top-of-screen ambient wash behind Home & Now Playing |

### Mood Accent Tints

- **All:** `#FF3B5C`
- **Energize:** `#FF5E3A`
- **Chill:** `#3B82F6`
- **Focus:** `#14B8A6`
- **Workout:** `#F59E0B`
- **Late Night:** `#8B5CF6`
- **Discover:** `#EC4899`

## Typography

Native Apple **SF Pro** (`Font.system(..., design: .default)`) + **SF Mono** for durations and bitrates:

- **Screen Title:** `32pt`, `.bold`, `-0.5` tracking
- **Section Header:** `20pt`, `.bold`, tight leading
- **Section Kicker:** `11pt`, `.semibold`, uppercase, `+1.1` tracking (`inkSecondary`)
- **Track Title:** `15pt`, `.semibold`, `1` line limit
- **Track Subtitle:** `13pt`, `.regular`, `inkSecondary`, `1` line limit
- **Pill / Badge:** `11pt–13pt`, `.semibold`
- **Timecodes:** `11pt`, `.monospacedDigit()`, `inkMuted`

## Layout, Spacing & Shape

- **Horizontal gutter:** `16pt` (`20pt` on Now Playing)
- **Section vertical rhythm:** `26pt` between major shelves
- **Corner radii:**
  - Speed Dial tiles: `12pt`
  - Quick Picks track artwork: `8pt`
  - Mix / Album cards: `16pt`
  - Artist portraits: `Circle()`
  - Floating Mini-Player: `18pt` floating `8pt` above tab bar
  - Now Playing hero artwork: `20pt` with soft `24pt` colored ambient shadow
- **Scrollbars:** Hidden everywhere (`.scrollIndicators(.hidden)`) for clean edge-to-edge scrolling.
- **Tap targets:** Minimum `44×44pt` hit areas on all playback, save, and star buttons.

## Motion & Accessibility

- **Spring transitions:** `Animation.spring(response: 0.34, dampingFraction: 0.84)` for play/pause scale, save-pill transitions, and tab/drawer swaps.
- **Reduced Motion:** Respect `@Environment(\.accessibilityReduceMotion)` — replace scale/spring transforms with crisp `0.15s` cross-dissolves.
- **Dynamic Type & VoiceOver:** Every icon-only button carries an explicit `.accessibilityLabel`; composite track rows group metadata via `.accessibilityElement(children: .combine)` while keeping action buttons independently reachable.

## Source & License Provenance

- Original design system authored for **Cadence** (`2026-11-27`), MIT licensed.
- Icons use native Apple **SF Symbols**.

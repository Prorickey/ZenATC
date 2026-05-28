# ZenATC — Codebase Guide

## What this app does

ZenATC mixes live ATC (Air Traffic Control) radio audio with lofi music so users can focus or relax with an airport ambience. A balance slider lets users dial between the two streams. The app is subscription-gated (monthly/annual via StoreKit) for premium airports.

---

## Tech Stack

| Layer | Tech |
|---|---|
| iOS app | SwiftUI, iOS 17+, AVFoundation |
| State management | `@Observable` (not ObservableObject) |
| In-app purchase | StoreKit 2 (`Product`, `Transaction`) |
| Auth | Firebase Auth |
| Lofi streaming | HLS via `AVPlayer`, served by Go backend |
| ATC audio | `AVAudioPlayer` loading from local bundle (transitioning to backend) |
| Backend | Go + Gin router + ffmpeg for HLS transcoding |

---

## Architecture

### State managers (all `@Observable` classes)

- **`AudioManager`** — owns both players. `isPlaying` toggle starts/pauses both. `balance` (0–1) sets volumes: `0` = full lofi, `1` = full ATC. Calling `reloadATC()` or `reloadLofi()` swaps the stream for the current selection.
- **`ThemeManager`** — holds the active `AppTheme` (background + foreground color pair). Passed via `.environment(themeManager)` and consumed with `@Environment(ThemeManager.self)`. Never passed as a parameter.
- **`AuthManager`** — thin Firebase Auth wrapper. `isSignedIn` / `userEmail` derived from `user: User?`.
- **`PurchaseManager`** — StoreKit 2. Checks `Transaction.currentEntitlements` to set `isPro`. Subscribes to `Transaction.updates` for renewals/refunds.
- **`VolumeMonitor`** (in `VolumeTooLowView.swift`) — wraps `AVAudioSession.outputVolume` via KVO. Updates `volume` on the main actor whenever system media volume changes.

### View hierarchy (ContentView.swift)

```
ContentView
├── TopBarView         — LIVE indicator, theme cycler, settings/airports buttons
├── AirportCarouselView — TabView paging through airports; receives a derived `dragY` from showTrackPicker
│   └── AirportPageView — one airport code letter scaled to fill container (ABCGravity font)
├── BottomControlsView
│   ├── MixerSliderView       — ATC/lofi balance pill-slider
│   ├── PlayPauseButton       — large circle play/pause
│   └── InlineTrackPicker     — custom drag-gesture wheel picker (rotated so selected is row 0)
├── SettingsView      (overlay, offset-animated)
├── UpgradeView       (overlay, .move transition)
├── AirportsListView  (overlay, .move transition)
├── OnboardingView    (overlay, zIndex 10) — currently disabled via hardcoded onAppear
└── VolumeTooLowView  (overlay, zIndex 20) — shows when system volume == 0; user can "Continue anyway"
```

### Picker animation contract (important)

`showTrackPicker` is the **single source of truth** for the entire selected ↔ swiped-up transition. Both the airport letter's compression (`dragY = showTrackPicker ? -200 : 0`, passed as a `let` into `AirportCarouselView`) and the slider/play offset key off this one Bool. Every code path that toggles it must use the unified spring `spring(response: 0.55, dampingFraction: 0.85)` (also stored as `BottomControlsView.pickerSpring`) so the letter and the bottom controls animate as one. Do not introduce a separate `@State` for the letter's compression; derive it from `showTrackPicker`.

### Gesture coordination

- `isSliderActive` (`@State` on ContentView, `@Binding` into `MixerSliderView`) gates the outer drag gesture — while the user is holding the pill, vertical drags won't open/close the picker.
- Vertical-vs-horizontal disambiguation: both the outer ContentView gesture and `AirportCarouselView`'s simultaneousGesture early-return when `|dx| ≥ |dy|` so horizontal TabView swipes don't trigger picker open/close.
- `MixerSliderView`'s `onChanged` ignores `|translation.width| < 5` so a tap on a new track spot doesn't cancel the in-flight spring animation from a previous tap.

### Haptics

- Light impact on `showTrackPicker` toggle (swipe up/down).
- Medium impact on `audio.currentAirportIndex` change.
- Selection haptic on `Int(balance * 20)` — ~21 quantized clicks as the slider pill drags.
- Selection haptic on `InlineTrackPicker.selectedIndex` via its own `.sensoryFeedback`.

### Data models (Models.swift)

- `Airport` — `code`, `name`, `city`, `atcFilename`, `isPro`
- `LofiTrack` — `name`, `filename` (used to build the HLS URL)

Both have static `.all` arrays; add new items there.

---

## Backend (Go)

Entry point: `backend/main.go`

- Auto-discovers every `.mp3` in `backend/audio/` and starts an ffmpeg HLS engine per file.
- ffmpeg reads each MP3 on an infinite loop and writes a rolling 5-segment playlist to `backend/live/<id>/`.
- Gin serves `/radio/<id>/index.m3u8` and `.ts` segments.
- To add a new lofi track: drop an `.mp3` into `backend/audio/` (filename = `lofi_<slug>.mp3`), restart the server, add a `LofiTrack` entry in `Models.swift`.

---

## Fonts

Registered at startup by `FontLoader` in `ZenATCApp.swift`. Two load paths are tried in order:
1. `NSDataAsset` (Assets.xcassets)
2. `.ttf` file in the `Fonts/` bundle subdirectory

Fonts in use:

| SwiftUI extension | PostScript name | Use |
|---|---|---|
| `.airportCode(size:)` | `ABCSchengenCoreVariable-Trial` | All UI labels |
| `.abcGravity(size:)` | `ABCGravityCyrillicUprightVariable-Trial` | Big airport letter |
| `.gtStandard(size:)` | `GT-Standard-Trial-VF` | (available, not widely used) |

---

## Key constraints and gotchas

- **`backendBaseURL` is a hardcoded LAN IP** (`192.168.1.87:8080`) in `AudioManager.swift`. Change this before any non-local build.
- **iOS 17+ only.** The code uses `@Observable`, `.scrollTargetBehavior(.viewAligned)`, `.scrollTransition`, `.sensoryFeedback`, and `AsyncSequence` (`Transaction.updates`).
- **`ThemeManager` is environment-only.** Never pass it as an init parameter; read it with `@Environment(ThemeManager.self)`.
- **`hasCompletedOnboarding` is forced true** in `ContentView.onAppear`. The `OnboardingView` is effectively disabled until that line is removed.
- **ATC audio is still in local bundle** (`ZenATC/Audio/*.mp3`) but is transitioning to backend streaming. `AudioManager.loadATC()` still loads from bundle.
- **`ABCGravityCyrillicUprightVariable-Trial`** font must be added manually (see comment in `Theme.swift`). The fallback is system black.

---

## Naming conventions

- View structs: `<Purpose>View` (e.g., `AirportsListView`, `UpgradeView`)
- Private sub-views inside a file: use `private struct` with a descriptive name, grouped under `// MARK:` sections
- Manager classes: `<Domain>Manager` (e.g., `AudioManager`, `ThemeManager`)
- Avoid public structs for view helpers — keep them `private` to their file

---

## Running locally

**Backend** (requires ffmpeg):
```sh
cd backend
go run main.go
```

**iOS app**: open `ZenATC.xcodeproj` in Xcode, update `backendBaseURL` in `AudioManager.swift` to your Mac's LAN IP, run on simulator or device.

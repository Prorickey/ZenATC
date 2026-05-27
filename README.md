# ZenATC

An iOS app that blends live ATC radio with lofi beats. Swipe through airports, mix the balance between ATC chatter and music, and cycle through colour themes.

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                    iOS App (SwiftUI)                 │
│                                                      │
│  Airport carousel ──► AVAudioPlayer (local ATC MP3) │
│  Lofi track picker ──► AVPlayer (HLS stream)         │
│  Mixer slider ──────► volume on both players         │
└──────────────────────┬───────────────────────────────┘
                       │ HTTP HLS
                       ▼
┌──────────────────────────────────────────────────────┐
│              Go / Gin Backend (:8080)                │
│                                                      │
│  ffmpeg loops each lofi MP3 → rolling HLS playlist  │
│  Gin serves live/<id>/ as static files               │
│  /radio/<id>/index.m3u8                              │
└──────────────────────────────────────────────────────┘
```

**ATC audio** is bundled in the app and played locally — no network required.  
**Lofi beats** are streamed from the Go backend as HLS, ready to sit behind a CDN.

---

## Project Structure

```
ZenATC/
├── ZenATC/                    # iOS app source
│   ├── Audio/                 # Bundled ATC clips (ATL, LAX, ORD, DFW, JFK)
│   ├── Assets.xcassets/       # Fonts (GT Standard, ABC Schengen) + app icon
│   ├── AudioManager.swift     # AVAudioPlayer (ATC) + AVPlayer (lofi HLS)
│   ├── ContentView.swift      # All SwiftUI views
│   ├── Models.swift           # Airport + LofiTrack data
│   ├── Theme.swift            # AppTheme, ThemeManager, font extensions
│   └── ZenATCApp.swift        # App entry point, font registration
└── backend/                   # Go streaming server
    ├── audio/                 # Source lofi MP3s
    ├── live/                  # ffmpeg HLS output (gitignored, auto-created)
    └── main.go                # Gin server + ffmpeg process management
```

---

## Requirements

- Xcode 16+ / iOS 18+
- Go 1.25+
- ffmpeg (`brew install ffmpeg`)

---

## Running the Backend

```bash
cd backend
go run .
```

The server starts on `:8080`. ffmpeg spawns one HLS engine per lofi MP3 found in `backend/audio/`. Streams are available after ~4 seconds of warm-up:

```
http://localhost:8080/radio/<id>/index.m3u8
```

| Stream ID         | Track            |
|-------------------|------------------|
| `lofi_late_night` | Late Night Study |
| `lofi_rainy_day`  | Rainy Day        |
| `lofi_work_flow`  | Work Flow        |
| `lofi_energy`     | Energy Boost     |

Health check: `GET http://localhost:8080/health`

---

## Running the iOS App

1. Open `ZenATC.xcodeproj` in Xcode
2. Select a simulator or connected device
3. Build and run (`⌘R`)

> **Physical device:** change `backendBaseURL` in `AudioManager.swift` from `localhost` to your Mac's LAN IP (e.g. `192.168.1.x`).

---

## Features

- **Airport carousel** — swipe between ATL, LAX, ORD, DFW, JFK; ATC audio switches instantly
- **Lofi track selector** — custom drag-based wheel picker with smooth size/opacity transitions
- **Mixer slider** — blend ATC chatter and lofi music; headphones icon = full lofi, airplane = full ATC
- **6 colour themes** — tap the palette icon to cycle through them
- **Play / Pause** — controls both audio streams simultaneously

---

## CDN Setup

The backend is CDN-ready out of the box. Cache-Control headers are already differentiated:

- `.m3u8` playlists — `no-cache, no-store` (revalidated every request)
- `.ts` segments — `public, max-age=600` (CDN caches for 10 minutes)

Point Cloudflare or CloudFront at `http://your-server:8080` and the CDN handles distribution automatically — your Go server only serves each segment once.

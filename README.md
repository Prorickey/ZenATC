# ZenATC

An iOS app that blends live ATC radio with lofi beats. Swipe through airports, mix the balance between ATC chatter and music, and cycle through colour themes. Background audio and lock screen controls included.

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
                       │ App Attest → signed CDN URL
                       ▼
┌──────────────────────────────────────────────────────┐
│         Cloudflare Worker (zenatc.bedson.tech)       │
│                                                      │
│  /hls/* — validates HMAC-SHA256 signed URLs          │
│  Strips query params before caching .ts segments     │
└──────────────────────┬───────────────────────────────┘
                       │ clean URL (no signature)
                       ▼
┌──────────────────────────────────────────────────────┐
│           Go / Gin Backend (:8080 → 3303)            │
│                                                      │
│  /attestation-challenge — JWT challenge for Attest   │
│  /attest-key       — registers App Attest public key │
│  /assert-and-stream — assertion-gated signed URL     │
│  /hls/*            — serves pre-sliced VOD segments  │
└──────────────────────────────────────────────────────┘
```

**ATC audio** is bundled in the app and played locally — no network required.  
**Lofi beats** are streamed as VOD HLS from Cloudflare CDN. Each 4-second `.ts` segment is cached at the edge. The app limits its local buffer to a 2-minute sliding window (~5MB) so played segments are evicted as new ones arrive.

---

## Security: App Attest

Audio streaming is gated by [Apple App Attest](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity). The flow:

1. **First launch**: iOS generates an attestation key, sends it to `/attest-key` with a signed JWT challenge — the backend verifies the CBOR attestation against Apple's root CA and stores the public key.
2. **Every track load**: iOS calls `generateAssertion` (no Apple server contact) and sends it to `/assert-and-stream` — the backend verifies the ECDSA signature against the stored key and returns a short-lived signed CDN URL.

The entitlements file (`ZenATC.entitlements`) is set to `development`. Change to `production` before App Store submission.

---

## Features

- **Onboarding** — guided 3-step intro (only shown once, persisted via `@AppStorage`)
- **Splash animation** — "lofi atc" flyby plays on every fresh app open
- **Audio preloading** — ATC and lofi streams are buffered during the splash so playback starts instantly
- **Fade-in** — 1.5s volume ramp when starting playback or adjusting the mixer during onboarding
- **Background audio** — playback continues when the screen locks or app is backgrounded (`UIBackgroundModes: audio`)
- **Lock screen / Control Center** — Now Playing metadata (track name, airport, app icon) with play/pause and track skip
- **Sliding-window cache** — URLCache capped at 5MB with 2-minute forward buffer; played segments are evicted automatically

---

## Project Structure

```
ZenATC/
├── ZenATC/                      # iOS app source
│   ├── Audio/                   # Bundled ATC clips (JFK, SFO, MIA, ORD, LAX, …)
│   ├── Assets.xcassets/         # Fonts, app icon, carousel images
│   ├── AttestationManager.swift # App Attest key lifecycle + assertion flow
│   ├── AudioManager.swift       # AVAudioPlayer (ATC) + AVPlayer (lofi HLS)
│   │                            #   + Now Playing / remote commands
│   │                            #   + fade-in, sliding-window cache
│   ├── ContentView.swift        # Root SwiftUI view + splash overlay
│   ├── OnboardingView.swift     # First-launch onboarding steps
│   ├── Models.swift             # Airport + LofiTrack data
│   ├── PurchaseManager.swift    # StoreKit 2 purchase flow
│   ├── SettingsView.swift       # Settings panel
│   ├── Theme.swift              # AppTheme, ThemeManager, font extensions
│   ├── ZenATC.entitlements      # App Attest + background audio capabilities
│   ├── Info.plist               # Background modes (audio)
│   └── ZenATCApp.swift          # App entry point
└── backend/                     # Go streaming server
    ├── audio/                   # Source lofi MP3s (not in git — copy manually)
    ├── cloudflare/              # Cloudflare Worker script + wrangler config
    ├── assertion.go             # App Attest assertion verification + key store
    ├── cdn.go                   # HMAC-SHA256 signed URL generation
    ├── challenge.go             # Stateless JWT challenge endpoint
    ├── main.go                  # Gin server + HLS file handler
    ├── verification.go          # Apple attestation CBOR verification
    ├── scripts/
    │   ├── docker.sh            # Local build/run + registry deploy
    │   ├── download.sh          # Download lofi MP3 sources
    │   ├── download_sections.sh # Download ATC audio sections
    │   ├── generate_hls.sh      # Manual HLS slicing (standalone)
    │   └── zenatc.conf          # nginx config for zenatc.bedson.tech
    ├── .env.example             # Environment variable template
    ├── docker-compose.yml       # Production deployment
    ├── Dockerfile               # Multi-stage build; generates HLS on first start
    └── docker-entrypoint.sh     # Auto-secrets + parallel HLS slicing
```

---

## Requirements

- Xcode 16+ / iOS 18+
- Go 1.25+
- Docker (for backend)
- ffmpeg (`brew install ffmpeg` — for local HLS generation only)

---

## Backend Setup

### Audio files

The source MP3s are not in git. Copy them to `backend/audio/` before starting the container:

```
backend/audio/
├── lofi_energy.mp3
├── lofi_late_night.mp3
├── lofi_rainy_day.mp3
└── lofi_work_flow.mp3
```

### Environment variables (`.env`)

Copy the template and fill in values:

```bash
cp backend/.env.example backend/.env
```

| Variable | Description |
|----------|-------------|
| `CLOUDFLARE_DOMAIN` | Domain serving HLS content |
| `CLOUDFLARE_URL_SIGNING_SECRET` | HMAC-SHA256 secret for signed CDN URLs (base64, 32+ bytes) |
| `CHALLENGE_SIGNING_SECRET` | HMAC-SHA256 secret for JWT challenges (base64, 32+ bytes) |
| `APPLE_APP_ID` | Team ID prefix + bundle identifier (e.g. `TEAMID.com.example.app`) |

Generate secrets with `openssl rand -base64 32`. The `CLOUDFLARE_URL_SIGNING_SECRET` must match the value set in the Cloudflare Worker (`wrangler secret put CLOUDFLARE_URL_SIGNING_SECRET`).

### Run locally

```bash
cd backend
./scripts/docker.sh run
```

Builds the image, generates HLS segments in parallel, and starts on port 3303.

### Deploy to production

```bash
cd backend
./scripts/docker.sh deploy   # build + push to registry
# on server:
docker compose up -d
```

### Cloudflare Worker

```bash
cd backend/cloudflare
wrangler secret put CLOUDFLARE_URL_SIGNING_SECRET   # same value as .env
wrangler deploy
```

---

## Running the iOS App

1. Open `ZenATC.xcodeproj` in Xcode
2. Select a connected device
3. Build and run (`⌘R`)

The app points to `https://zenatc.bedson.tech` by default (`backendBaseURL` in `AudioManager.swift`).

---

## API

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Health check |
| `GET` | `/attestation-challenge` | Issues JWT challenge for App Attest |
| `POST` | `/attest-key` | Registers App Attest public key |
| `POST` | `/assert-and-stream` | Assertion-gated signed CDN URL |
| `GET` | `/hls/:id/index.m3u8` | HLS playlist |
| `GET` | `/hls/:id/seg_*.ts` | HLS segment (immutable, CDN-cached) |

| Stream ID | Track |
|-----------|-------|
| `lofi_late_night` | Late Night Study |
| `lofi_rainy_day` | Rainy Day |
| `lofi_work_flow` | Work Flow |
| `lofi_energy` | Energy Boost |

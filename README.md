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
**Lofi beats** are streamed as VOD HLS from Cloudflare CDN. Each 4-second `.ts` segment is cached permanently at the edge; second playthrough is fully offline.

---

## Security: App Attest

Audio streaming is gated by [Apple App Attest](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity). The flow:

1. **First launch**: iOS generates an attestation key, sends it to `/attest-key` with a signed JWT challenge — the backend verifies the CBOR attestation against Apple's root CA and stores the public key.
2. **Every track load**: iOS calls `generateAssertion` (no Apple server contact) and sends it to `/assert-and-stream` — the backend verifies the ECDSA signature against the stored key and returns a short-lived signed CDN URL.

The entitlements file (`ZenATC.entitlements`) is set to `development`. Change to `production` before App Store submission.

---

## Project Structure

```
ZenATC/
├── ZenATC/                      # iOS app source
│   ├── Audio/                   # Bundled ATC clips (JFK, SFO, MIA, ORD, LAX, …)
│   ├── Assets.xcassets/         # Fonts, app icon, carousel images
│   ├── AttestationManager.swift # App Attest key lifecycle + assertion flow
│   ├── AudioManager.swift       # AVAudioPlayer (ATC) + AVPlayer (lofi HLS)
│   ├── ContentView.swift        # Root SwiftUI view
│   ├── Models.swift             # Airport + LofiTrack data
│   ├── PurchaseManager.swift    # StoreKit 2 purchase flow
│   ├── Theme.swift              # AppTheme, ThemeManager, font extensions
│   └── ZenATCApp.swift          # App entry point
└── backend/                     # Go streaming server
    ├── audio/                   # Source lofi MP3s (not in git — copy manually)
    ├── cloudflare/              # Cloudflare Worker script + wrangler config
    ├── assertion.go             # App Attest assertion verification + key store
    ├── cdn.go                   # HMAC-SHA256 signed URL generation
    ├── challenge.go             # Stateless JWT challenge endpoint
    ├── main.go                  # Gin server + HLS file handler
    ├── verification.go          # Apple attestation CBOR verification
    ├── docker-compose.yml       # Production deployment
    ├── docker.sh                # Local build/run + registry deploy
    ├── Dockerfile               # Multi-stage build; generates HLS on first start
    ├── docker-entrypoint.sh     # Auto-secrets + parallel HLS slicing
    └── zenatc.conf              # nginx config for zenatc.bedson.tech
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

```
CLOUDFLARE_DOMAIN=zenatc.bedson.tech
CLOUDFLARE_URL_SIGNING_SECRET=<base64-encoded 32 bytes>
CHALLENGE_SIGNING_SECRET=<base64-encoded 32 bytes>
```

Generate secrets with `openssl rand -base64 32`. The `CLOUDFLARE_URL_SIGNING_SECRET` must match the value set in the Cloudflare Worker (`wrangler secret put CLOUDFLARE_URL_SIGNING_SECRET`).

### Run locally

```bash
cd backend
./docker.sh run
```

Builds the image, generates HLS segments in parallel, and starts on port 3303.

### Deploy to production

```bash
cd backend
./docker.sh deploy         # build + push to registry
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

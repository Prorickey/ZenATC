#!/bin/sh
set -e

# ── Signing secrets ──────────────────────────────────────────────────────────

generate_secret() {
    name="$1"
    eval val="\$$name"
    if [ -z "$val" ]; then
        generated="$(openssl rand -base64 32)"
        eval export "$name=$generated"
        echo "[startup] Generated new $name"
    else
        echo "[startup] Using injected $name"
    fi
}

generate_secret CHALLENGE_SIGNING_SECRET
# A random 32-byte seed is a valid Ed25519 key, so this lets the backend start in
# dev without config. In production it MUST be injected to match the Worker's
# public key (a random per-restart key would make the Worker reject every URL).
generate_secret CLOUDFLARE_URL_SIGNING_PRIVATE_KEY

# ── HLS generation ───────────────────────────────────────────────────────────
# Slice each MP3 into 4-second VOD segments on first start.
# If audio/hls/<id>/index.m3u8 already exists (e.g. from a mounted volume)
# the track is skipped, so restarts are fast.

mkdir -p audio/hls

slice() {
    f="$1"
    id=$(basename "$f" .mp3)
    if [ -f "audio/hls/$id/index.m3u8" ]; then
        echo "[hls] $id already sliced, skipping"
        return
    fi
    echo "[hls] Slicing $id ..."
    mkdir -p "audio/hls/$id"
    ffmpeg -y -i "$f" \
        -c:a aac -b:a 128k \
        -f hls \
        -hls_time 4 \
        -hls_playlist_type vod \
        -hls_segment_filename "audio/hls/$id/seg_%03d.ts" \
        "audio/hls/$id/index.m3u8" \
        -loglevel error
    echo "[hls] $id done"
}

if ls audio/*.mp3 >/dev/null 2>&1; then
    for f in audio/*.mp3; do
        slice "$f" &
    done
    wait
else
    echo "[hls] No MP3 files found in /app/audio"
fi

echo "[hls] All tracks ready"

# ── Start server ─────────────────────────────────────────────────────────────

exec "$@"

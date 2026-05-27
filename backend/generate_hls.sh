#!/bin/sh
# Regenerates VOD HLS segments from all MP3s in audio/.
# Run this locally after adding or replacing a source MP3.
# The Docker build runs the equivalent automatically.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

mkdir -p audio/hls

MAX_JOBS="${MAX_JOBS:-4}"

if ! ls audio/*.mp3 >/dev/null 2>&1; then
    echo "No MP3 files found in audio/"
    exit 0
fi

find audio -maxdepth 1 -type f -name "*.mp3" -print0 | xargs -0 -n 1 -P "$MAX_JOBS" sh -ec '
    f="$1"
    id=$(basename "$f" .mp3)
    echo "Slicing $id"
    mkdir -p "audio/hls/$id"
    ffmpeg -y -i "$f" \
        -c:a aac -b:a 128k \
        -f hls \
        -hls_time 4 \
        -hls_playlist_type vod \
        -hls_segment_filename "audio/hls/$id/seg_%03d.ts" \
        "audio/hls/$id/index.m3u8"
    echo "  $(ls audio/hls/$id/*.ts | wc -l | tr -d " ") segments"
' sh

echo "Done."

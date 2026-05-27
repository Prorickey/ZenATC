#!/usr/bin/env bash
set -euo pipefail

URLS=(
  "https://www.youtube.com/watch?v=1J4a9cT2lkw"
  "https://www.youtube.com/watch?v=JCKBaJDRMw4"
  "https://www.youtube.com/watch?v=lTRiuFIWV54"
  "https://www.youtube.com/watch?v=TSA6GD9MioM"
)

DURATION="00:15:00"
OUTPUT_DIR="./output"

mkdir -p "$OUTPUT_DIR"

for url in "${URLS[@]}"; do
  echo "Downloading: $url"

  # Download best audio and convert to mp3, saving with video title
  yt-dlp \
    --extract-audio \
    --audio-format mp3 \
    --audio-quality 0 \
    --output "$OUTPUT_DIR/%(title)s.%(ext)s" \
    "$url"
done

echo "Trimming all MP3s to first 15 minutes..."

for mp3 in "$OUTPUT_DIR"/*.mp3; do
  trimmed="${mp3%.mp3}_trimmed.mp3"
  echo "Trimming: $(basename "$mp3")"
  ffmpeg -y -i "$mp3" -t "$DURATION" -acodec copy "$trimmed" 2>/dev/null
  # Replace original with trimmed
  mv "$trimmed" "$mp3"
done

echo "Done. Files saved to $OUTPUT_DIR/"

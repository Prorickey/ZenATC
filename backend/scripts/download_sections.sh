#!/usr/bin/env bash
set -euo pipefail

URL="https://www.youtube.com/watch?v=Mfh_b4ZPkKs"
OUTPUT_DIR="./output_sections"
SECTION_LENGTH=900  # 15 minutes in seconds

mkdir -p "$OUTPUT_DIR"

echo "Downloading: $URL"

yt-dlp \
  --extract-audio \
  --audio-format mp3 \
  --audio-quality 0 \
  --output "$OUTPUT_DIR/full.mp3" \
  "$URL"

echo "Splitting into 5 x 15-minute sections..."

for i in $(seq 1 5); do
  start=$(( (i - 1) * SECTION_LENGTH ))
  output="$OUTPUT_DIR/section_$(printf '%02d' $i).mp3"
  echo "  Section $i: $(( start / 60 ))m -> $(( (start + SECTION_LENGTH) / 60 ))m => $(basename "$output")"
  ffmpeg -y -i "$OUTPUT_DIR/full.mp3" -ss "$start" -t "$SECTION_LENGTH" -acodec copy "$output" 2>/dev/null
done

echo "Removing full download..."
rm "$OUTPUT_DIR/full.mp3"

echo "Done. Sections saved to $OUTPUT_DIR/"

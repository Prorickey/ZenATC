#!/usr/bin/env bash
set -euo pipefail

URLS=(
  "https://www.youtube.com/watch?v=1J4a9cT2lkw"
  "https://www.youtube.com/watch?v=JCKBaJDRMw4"
  "https://www.youtube.com/watch?v=lTRiuFIWV54"
  "https://www.youtube.com/watch?v=TSA6GD9MioM"
)

NAMES=(
  "lofi_energy"
  "lofi_late_night"
  "lofi_rainy_day"
  "lofi_work_flow"
)

OUTPUT_DIR="./output"
MAX_JOBS="${MAX_JOBS:-4}"

mkdir -p "$OUTPUT_DIR"

download_one() {
  local url="$1"
  local name="$2"

  echo "Downloading: $url"

  # Download best audio and convert to mp3, saving with fixed output name
  yt-dlp \
    --extract-audio \
    --audio-format mp3 \
    --audio-quality 0 \
    --output "$OUTPUT_DIR/${name}.%(ext)s" \
    "$url"
}

pids=()

if (( ${#URLS[@]} != ${#NAMES[@]} )); then
  echo "URLS and NAMES length mismatch"
  exit 1
fi

for i in "${!URLS[@]}"; do
  download_one "${URLS[$i]}" "${NAMES[$i]}" &
  pids+=("$!")

  if (( ${#pids[@]} >= MAX_JOBS )); then
    wait "${pids[0]}"
    pids=("${pids[@]:1}")
  fi
done

for pid in "${pids[@]}"; do
  wait "$pid"
done

echo "Done. Files saved to $OUTPUT_DIR/"

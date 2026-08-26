#!/bin/bash
set -uo pipefail

TARGETS_FILE=/etc/mediamtx/restream.targets
INPUT="rtmp://127.0.0.1:1935/${MTX_PATH}"
PIDS=()

trap 'kill 0' INT TERM

if [ ! -r "$TARGETS_FILE" ]; then
  echo "Targets file $TARGETS_FILE missing or unreadable, exiting"
  exit 0
fi

restream_one() {
  local url="$1"
  local fmt
  case "$url" in
    rtmp://*|rtmps://*) fmt=flv ;;
    srt://*)            fmt=mpegts ;;
    *)
      echo "Unsupported URL scheme, skipping: $url"
      return
      ;;
  esac
  while true; do
    ffmpeg -i "$INPUT" -c copy -f "$fmt" "$url"
    echo "Stream to $url ended, restarting in 1s..."
    sleep 1
  done
}

while IFS= read -r line || [ -n "$line" ]; do
  # strip leading/trailing whitespace
  url="${line#"${line%%[![:space:]]*}"}"
  url="${url%"${url##*[![:space:]]}"}"
  [ -z "$url" ] && continue
  case "$url" in \#*) continue ;; esac

  restream_one "$url" &
  PIDS+=($!)
done < "$TARGETS_FILE"

if [ ${#PIDS[@]} -eq 0 ]; then
  echo "No restream targets configured, exiting"
  exit 0
fi

wait

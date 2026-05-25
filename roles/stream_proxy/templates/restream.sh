#!/bin/bash
set -uo pipefail

source /etc/mediamtx/restream.env

INPUT="rtmp://127.0.0.1:1935/${MTX_PATH}"
PIDS=()

trap 'kill 0' INT TERM

if [ -n "${RESTREAM_YOUTUBE_KEY:-}" ]; then
  (while true; do
    ffmpeg -i "$INPUT" -c copy -f flv "rtmp://a.rtmp.youtube.com/live2/${RESTREAM_YOUTUBE_KEY}"
    echo "YouTube stream ended, restarting in 2s..."
    sleep 2
  done) &
  PIDS+=($!)
fi

if [ -n "${RESTREAM_FACEBOOK_KEY:-}" ]; then
  (while true; do
    ffmpeg -i "$INPUT" -c copy -f flv "rtmps://live-api-s.facebook.com:443/rtmp/${RESTREAM_FACEBOOK_KEY}"
    echo "Facebook stream ended, restarting in 2s..."
    sleep 2
  done) &
  PIDS+=($!)
fi

if [ ${#PIDS[@]} -eq 0 ]; then
  echo "No restream targets configured, exiting"
  exit 0
fi

wait

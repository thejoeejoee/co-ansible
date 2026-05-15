#!/bin/bash
set -uo pipefail

source /etc/mediamtx/restream.env

OUTPUTS=()

if [ -n "${RESTREAM_YOUTUBE_KEY:-}" ]; then
  OUTPUTS+=(-c copy -f flv "rtmp://a.rtmp.youtube.com/live2/${RESTREAM_YOUTUBE_KEY}")
fi

if [ -n "${RESTREAM_FACEBOOK_KEY:-}" ]; then
  OUTPUTS+=(-c copy -f flv "rtmps://live-api-s.facebook.com:443/rtmp/${RESTREAM_FACEBOOK_KEY}")
fi

if [ ${#OUTPUTS[@]} -eq 0 ]; then
  echo "No restream targets configured, exiting"
  exit 0
fi

exec ffmpeg -i "rtmp://127.0.0.1:1935/${MTX_PATH}" "${OUTPUTS[@]}"

#!/usr/bin/env bash
set -euo pipefail

interval="${SCHEDULER_INTERVAL:-60}"

if ! [[ "$interval" =~ ^[0-9]+$ ]] || [[ "$interval" -le 0 ]]; then
  echo "Invalid SCHEDULER_INTERVAL: $interval" >&2
  interval=60
fi

shutdown_requested=false
trap 'shutdown_requested=true' TERM INT

while true; do
  if ! php /var/www/html/cron.php; then
    status=$?
    echo "[scheduler] cron.php exited with status $status" >&2
  fi

  if $shutdown_requested; then
    break
  fi

  sleep "$interval" &
  wait $! || true

  if $shutdown_requested; then
    break
  fi

done

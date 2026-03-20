#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") <attempts> <delay-seconds> <command> [args...]
EOF
}

if [[ $# -lt 3 ]]; then
  usage >&2
  exit 1
fi

ATTEMPTS="$1"
DELAY_SECONDS="$2"
shift 2

if ! [[ "$ATTEMPTS" =~ ^[1-9][0-9]*$ ]]; then
  echo "attempts must be a positive integer: $ATTEMPTS" >&2
  exit 1
fi

if ! [[ "$DELAY_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "delay-seconds must be a non-negative integer: $DELAY_SECONDS" >&2
  exit 1
fi

for attempt in $(seq 1 "$ATTEMPTS"); do
  if "$@"; then
    exit 0
  fi

  if [[ "$attempt" == "$ATTEMPTS" ]]; then
    break
  fi

  echo "Attempt $attempt/$ATTEMPTS failed; retrying in ${DELAY_SECONDS}s..." >&2
  sleep "$DELAY_SECONDS"
done

echo "Command failed after $ATTEMPTS attempts: $*" >&2
exit 1

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/Vendor/ghostty-runtime.env"
CACHE_ROOT="${TAIRI_GHOSTTY_CACHE_ROOT:-$ROOT/.local/vendor/Ghostty}"

load_manifest() {
  if [[ ! -f "$MANIFEST" ]]; then
    echo "Missing Ghostty manifest: $MANIFEST" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  source "$MANIFEST"

  if [[ -z "${GHOSTTY_VERSION:-}" ]]; then
    echo "Ghostty manifest must define GHOSTTY_VERSION" >&2
    exit 1
  fi
}

runtime_dir() {
  printf '%s\n' "$CACHE_ROOT/$GHOSTTY_VERSION"
}

runtime_is_cached() {
  local dir
  dir="$(runtime_dir)"

  [[ -x "$dir/GhosttyRuntime.app/Contents/MacOS/ghostty" ]] \
    && [[ -d "$dir/GhosttyRuntime.app/Contents/Resources/ghostty" ]]
}

load_manifest

if ! runtime_is_cached; then
  "$ROOT/scripts/vendor-ghostty.sh"
fi

runtime_dir

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="tairi.app"
SOURCE_APP="$ROOT/dist/$APP_NAME"
DEFAULT_TARGET_DIR="/Applications"
FALLBACK_TARGET_DIR="$HOME/Applications"

install_to() {
  local target_dir="$1"
  local target_app="$target_dir/$APP_NAME"

  mkdir -p "$target_dir"

  if [[ -e "$target_app" ]]; then
    if ! command -v trash >/dev/null 2>&1; then
      echo "trash is required to replace an existing install at $target_app" >&2
      return 1
    fi

    trash "$target_app"
  fi

  ditto "$SOURCE_APP" "$target_app"
  codesign --verify --deep --strict "$target_app"
  echo "Installed $target_app"
}

"$ROOT/scripts/build-app.sh"

if [[ $# -gt 0 ]]; then
  install_to "$1"
  exit 0
fi

if install_to "$DEFAULT_TARGET_DIR"; then
  exit 0
fi

install_to "$FALLBACK_TARGET_DIR"

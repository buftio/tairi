#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/release-config.sh"

APP_NAME="${TAIRI_APP_NAME}.app"
SOURCE_APP="$ROOT/dist/$APP_NAME"
SYSTEM_TARGET_DIR="/Applications"
USER_TARGET_DIR="$HOME/Applications"
KNOWN_TARGET_DIRS=("$SYSTEM_TARGET_DIR" "$USER_TARGET_DIR")

require_trash() {
  if ! command -v trash >/dev/null 2>&1; then
    echo "trash is required to replace or deduplicate installed app bundles" >&2
    exit 1
  fi
}

canonical_path() {
  python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

remove_app_if_present() {
  local app_path="$1"

  [[ -e "$app_path" ]] || return 0

  require_trash
  trash "$app_path"
  echo "Removed stale install at $app_path"
}

resolve_target_dir() {
  printf '%s\n' "$USER_TARGET_DIR"
}

remove_duplicate_installs() {
  local target_dir="$1"
  local canonical_target_dir
  canonical_target_dir="$(canonical_path "$target_dir")"

  for candidate_dir in "${KNOWN_TARGET_DIRS[@]}"; do
    local candidate_path="$candidate_dir/$APP_NAME"
    local canonical_candidate_dir
    canonical_candidate_dir="$(canonical_path "$candidate_dir")"

    if [[ "$canonical_candidate_dir" == "$canonical_target_dir" ]]; then
      continue
    fi

    remove_app_if_present "$candidate_path"
  done
}

install_to() {
  local target_dir="$1"
  local target_app="$target_dir/$APP_NAME"

  mkdir -p "$target_dir"
  remove_duplicate_installs "$target_dir"

  if [[ -e "$target_app" ]]; then
    remove_app_if_present "$target_app"
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

install_to "$(resolve_target_dir)"

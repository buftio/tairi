#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_IMAGE="${1:-$ROOT/Assets/AppIcon.png}"
OUTPUT_ICNS="${2:-$ROOT/dist/AppIcon.icns}"
ICONSET_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tairi-appicon.XXXXXX")"
ICONSET_DIR="$ICONSET_ROOT/AppIcon.iconset"

cleanup() {
  if command -v trash >/dev/null 2>&1; then
    trash "$ICONSET_ROOT" >/dev/null 2>&1 || true
  else
    rm -rf "$ICONSET_ROOT"
  fi
}

trap cleanup EXIT

if [[ ! -f "$SOURCE_IMAGE" ]]; then
  echo "App icon source not found: $SOURCE_IMAGE" >&2
  exit 1
fi

mkdir -p "$ICONSET_DIR" "$(dirname "$OUTPUT_ICNS")"

render_icon() {
  local size="$1"
  local name="$2"
  sips -z "$size" "$size" "$SOURCE_IMAGE" --out "$ICONSET_DIR/$name" >/dev/null
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"

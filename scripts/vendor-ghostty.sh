#!/usr/bin/env bash
# Vendor a pinned Ghostty runtime into a repo-local cache so development and
# packaged builds use the same bundle-like runtime layout and code-signing
# behavior without committing binaries to git.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/Vendor/ghostty-runtime.env"
CACHE_ROOT="${TAIRI_GHOSTTY_CACHE_ROOT:-$ROOT/.local/vendor/Ghostty}"
DOWNLOAD_ROOT="${TAIRI_GHOSTTY_DOWNLOAD_ROOT:-$ROOT/.local/cache/ghostty}"
MOUNT_ROOT="${TAIRI_GHOSTTY_MOUNT_ROOT:-$ROOT/.local/tmp/ghostty-mount}"

require_trash() {
  if ! command -v trash >/dev/null 2>&1; then
    echo "trash is required to replace cached Ghostty runtimes" >&2
    exit 1
  fi
}

load_manifest() {
  if [[ ! -f "$MANIFEST" ]]; then
    echo "Missing Ghostty manifest: $MANIFEST" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  source "$MANIFEST"

  if [[ -z "${GHOSTTY_VERSION:-}" || -z "${GHOSTTY_URL:-}" || -z "${GHOSTTY_SHA256:-}" ]]; then
    echo "Ghostty manifest must define GHOSTTY_VERSION, GHOSTTY_URL, and GHOSTTY_SHA256" >&2
    exit 1
  fi
}

checksum_file() {
  shasum -a 256 "$1" | awk '{ print $1 }'
}

verify_checksum() {
  local file="$1"
  local actual
  actual="$(checksum_file "$file")"
  if [[ "$actual" != "$GHOSTTY_SHA256" ]]; then
    echo "Checksum mismatch for $file" >&2
    echo "Expected: $GHOSTTY_SHA256" >&2
    echo "Actual:   $actual" >&2
    exit 1
  fi
}

download_official_release() {
  local dmg_path="$DOWNLOAD_ROOT/Ghostty-$GHOSTTY_VERSION.dmg"
  mkdir -p "$DOWNLOAD_ROOT"

  if [[ -f "$dmg_path" ]]; then
    verify_checksum "$dmg_path"
    echo "$dmg_path"
    return 0
  fi

  local partial="$dmg_path.partial"
  rm -f "$partial"
  curl -L --fail --output "$partial" "$GHOSTTY_URL"
  mv "$partial" "$dmg_path"
  verify_checksum "$dmg_path"
  echo "$dmg_path"
}

vendor_from_dmg() {
  local dmg_path="$1"
  local mount_point="$MOUNT_ROOT/$GHOSTTY_VERSION-$$"
  mkdir -p "$mount_point"
  hdiutil attach "$dmg_path" -nobrowse -readonly -mountpoint "$mount_point" >/dev/null
  trap 'hdiutil detach "$mount_point" >/dev/null 2>&1 || true' RETURN

  local app_path="$mount_point/Ghostty.app"
  if [[ ! -d "$app_path" ]]; then
    echo "Ghostty.app not found inside mounted DMG: $dmg_path" >&2
    exit 1
  fi

  local dest="$CACHE_ROOT/$GHOSTTY_VERSION"

  mkdir -p "$dest"
  require_trash
  if [[ -d "$dest/GhosttyRuntime.app" ]]; then
    trash "$dest/GhosttyRuntime.app"
  fi

  mkdir -p "$dest/GhosttyRuntime.app/Contents/MacOS" \
           "$dest/GhosttyRuntime.app/Contents/Frameworks" \
           "$dest/GhosttyRuntime.app/Contents/Resources"

  cp "$app_path/Contents/MacOS/ghostty" "$dest/GhosttyRuntime.app/Contents/MacOS/ghostty"
  cp -R "$app_path/Contents/Frameworks/Sparkle.framework" "$dest/GhosttyRuntime.app/Contents/Frameworks/"
  cp -R "$app_path/Contents/Resources/ghostty" "$dest/GhosttyRuntime.app/Contents/Resources/"
  cp "$app_path/Contents/Info.plist" "$dest/GhosttyRuntime.app/Contents/Info.plist"

  cat > "$dest/VERSION.txt" <<EOF
$GHOSTTY_VERSION
EOF

  codesign --force --deep --sign - "$dest/GhosttyRuntime.app" >/dev/null 2>&1 || true

  echo "Vendored Ghostty $GHOSTTY_VERSION to $dest"
}

load_manifest

vendor_from_dmg "$(download_official_release)"

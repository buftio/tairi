#!/usr/bin/env bash
# Build a distributable tairi.app, embed the vendored Ghostty runtime as a
# nested helper app, and sign the resulting bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/release-config.sh"

BUILD_CONFIGURATION="${TAIRI_BUILD_CONFIGURATION:-release}"
BUILD_DIR="$ROOT/.build/$BUILD_CONFIGURATION"
DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/$TAIRI_APP_NAME.app"
GHOSTTY_APP_DIR="$APP_DIR/Contents/Frameworks/GhosttyRuntime.app"
APP_ICON_SOURCE="$ROOT/Assets/AppIcon.png"
APP_ICON_PATH="$APP_DIR/Contents/Resources/AppIcon.icns"
LEGAL_DIR="$APP_DIR/Contents/Resources/ThirdPartyNotices"
CACHE_ROOT="${TAIRI_GHOSTTY_CACHE_ROOT:-$ROOT/.local/vendor/Ghostty}"
GHOSTTY_MANIFEST="$ROOT/Vendor/ghostty-runtime.env"
CODESIGN_IDENTITY="${TAIRI_CODESIGN_IDENTITY:--}"
THIRD_PARTY_NOTICES_SOURCE="$ROOT/THIRD_PARTY_NOTICES.md"
TAIRI_LICENSE_SOURCE="$ROOT/LICENSE"
GHOSTTY_LICENSE_SOURCE="$ROOT/Vendor/licenses/Ghostty-LICENSE.txt"
SPARKLE_LICENSE_SOURCE="$ROOT/Vendor/licenses/Sparkle-LICENSE.txt"

trash_path_if_present() {
  local path="$1"

  [[ -e "$path" ]] || return 0

  if ! command -v trash >/dev/null 2>&1; then
    echo "trash is required to replace existing app bundles: $path" >&2
    exit 1
  fi

  trash "$path"
}

sign_path() {
  local path="$1"
  shift

  local -a args=(--force --sign "$CODESIGN_IDENTITY")
  if [[ "$CODESIGN_IDENTITY" != "-" ]]; then
    args+=(--timestamp --options runtime)
  fi

  codesign "${args[@]}" "$@" "$path"
}

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "Missing required file: $path" >&2
    exit 1
  fi
}

if [[ ! -f "$GHOSTTY_MANIFEST" ]]; then
  echo "Missing Ghostty manifest: $GHOSTTY_MANIFEST" >&2
  exit 1
fi

require_file "$THIRD_PARTY_NOTICES_SOURCE"
require_file "$TAIRI_LICENSE_SOURCE"
require_file "$GHOSTTY_LICENSE_SOURCE"
require_file "$SPARKLE_LICENSE_SOURCE"

# shellcheck disable=SC1090
source "$GHOSTTY_MANIFEST"

if [[ -z "${GHOSTTY_VERSION:-}" ]]; then
  echo "Ghostty manifest must define GHOSTTY_VERSION" >&2
  exit 1
fi

"$ROOT/scripts/ensure-ghostty.sh" >/dev/null

VERSION_DIR="$CACHE_ROOT/$GHOSTTY_VERSION"
if [[ ! -d "$VERSION_DIR/GhosttyRuntime.app" ]]; then
  echo "Pinned Ghostty runtime $GHOSTTY_VERSION not found under $CACHE_ROOT" >&2
  exit 1
fi

swift build --configuration "$BUILD_CONFIGURATION" --package-path "$ROOT"

trash_path_if_present "$APP_DIR"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks" "$LEGAL_DIR"

cp "$BUILD_DIR/$TAIRI_APP_NAME" "$APP_DIR/Contents/MacOS/$TAIRI_APP_NAME"
cp -R "$VERSION_DIR/GhosttyRuntime.app" "$GHOSTTY_APP_DIR"
cp -R "$VERSION_DIR/GhosttyRuntime.app/Contents/Resources/ghostty" "$APP_DIR/Contents/Resources/"
"$ROOT/scripts/render-app-icon.sh" "$APP_ICON_SOURCE" "$APP_ICON_PATH"
cp "$THIRD_PARTY_NOTICES_SOURCE" "$LEGAL_DIR/THIRD_PARTY_NOTICES.md"
cp "$TAIRI_LICENSE_SOURCE" "$LEGAL_DIR/Tairi-LICENSE.txt"
cp "$GHOSTTY_LICENSE_SOURCE" "$LEGAL_DIR/Ghostty-LICENSE.txt"
cp "$SPARKLE_LICENSE_SOURCE" "$LEGAL_DIR/Sparkle-LICENSE.txt"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${TAIRI_APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${TAIRI_BUNDLE_ID}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${TAIRI_APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${TAIRI_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${TAIRI_BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key>
  <string>${TAIRI_MIN_MACOS}</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

sign_path "$GHOSTTY_APP_DIR" --deep
sign_path "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "Built $APP_DIR using vendored Ghostty $GHOSTTY_VERSION from $VERSION_DIR"

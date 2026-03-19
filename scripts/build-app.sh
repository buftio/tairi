#!/usr/bin/env bash
# Build a distributable tairi.app, embed the vendored Ghostty runtime as a
# nested helper app, copy Ghostty resources, and ad-hoc sign the result.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="tairi"
BUILD_DIR="$ROOT/.build/debug"
DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
GHOSTTY_APP_DIR="$APP_DIR/Contents/Frameworks/GhosttyRuntime.app"
APP_ICON_SOURCE="$ROOT/Assets/AppIcon.png"
APP_ICON_PATH="$APP_DIR/Contents/Resources/AppIcon.icns"
CACHE_ROOT="${TAIRI_GHOSTTY_CACHE_ROOT:-$ROOT/.local/vendor/Ghostty}"

if [[ ! -d "$CACHE_ROOT" ]]; then
  "$ROOT/scripts/vendor-ghostty.sh"
fi

VERSION_DIR="$(find "$CACHE_ROOT" -mindepth 1 -maxdepth 1 -type d | sort | tail -1)"
if [[ -z "$VERSION_DIR" ]]; then
  echo "No cached Ghostty runtime found under $CACHE_ROOT" >&2
  exit 1
fi

swift build --package-path "$ROOT"

if [[ -d "$APP_DIR" ]]; then
  if command -v trash >/dev/null 2>&1; then
    trash "$APP_DIR"
  else
    rm -rf "$APP_DIR"
  fi
fi

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"

cp "$BUILD_DIR/tairi" "$APP_DIR/Contents/MacOS/tairi"
cp -R "$VERSION_DIR/GhosttyRuntime.app" "$GHOSTTY_APP_DIR"
cp -R "$VERSION_DIR/GhosttyRuntime.app/Contents/Resources/ghostty" "$APP_DIR/Contents/Resources/"
"$ROOT/scripts/render-app-icon.sh" "$APP_ICON_SOURCE" "$APP_ICON_PATH"

cat > "$APP_DIR/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>tairi</string>
  <key>CFBundleIdentifier</key>
  <string>org.tairi.app</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>tairi</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$GHOSTTY_APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "Built $APP_DIR using vendored Ghostty from $VERSION_DIR"

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

if [[ ! -d "$ROOT/Vendor/Ghostty" ]]; then
  echo "No vendored Ghostty runtime found. Run scripts/vendor-ghostty.sh first." >&2
  exit 1
fi

VERSION_DIR="$(find "$ROOT/Vendor/Ghostty" -mindepth 1 -maxdepth 1 -type d | sort | tail -1)"
if [[ -z "$VERSION_DIR" ]]; then
  echo "No vendored Ghostty version directory found." >&2
  exit 1
fi

swift build --package-path "$ROOT"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"

cp "$BUILD_DIR/tairi" "$APP_DIR/Contents/MacOS/tairi"
cp -R "$VERSION_DIR/GhosttyRuntime.app" "$GHOSTTY_APP_DIR"
cp -R "$VERSION_DIR/GhosttyRuntime.app/Contents/Resources/ghostty" "$APP_DIR/Contents/Resources/"

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
  <string>dev.buft.tairi</string>
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

codesign --force --deep --sign - "$GHOSTTY_APP_DIR" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Built $APP_DIR using vendored Ghostty from $VERSION_DIR"

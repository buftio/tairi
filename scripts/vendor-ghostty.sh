#!/usr/bin/env bash
# Vend a pinned Ghostty runtime from a source Ghostty.app into Vendor/Ghostty/
# as a nested GhosttyRuntime.app so development and packaged builds use the
# same bundle-like runtime layout and code-signing behavior.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="${1:-/Applications/Ghostty.app}"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Ghostty app not found at: $SOURCE_APP" >&2
  exit 1
fi

VERSION="$(defaults read "$SOURCE_APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_APP/Contents/Info.plist")"
DEST="$ROOT/Vendor/Ghostty/$VERSION"

if [[ -d "$DEST/GhosttyRuntime.app" ]]; then
  trash "$DEST/GhosttyRuntime.app"
fi

mkdir -p "$DEST/GhosttyRuntime.app/Contents/MacOS" \
         "$DEST/GhosttyRuntime.app/Contents/Frameworks" \
         "$DEST/GhosttyRuntime.app/Contents/Resources"

cp "$SOURCE_APP/Contents/MacOS/ghostty" "$DEST/GhosttyRuntime.app/Contents/MacOS/ghostty"
cp -R "$SOURCE_APP/Contents/Frameworks/Sparkle.framework" "$DEST/GhosttyRuntime.app/Contents/Frameworks/"
cp -R "$SOURCE_APP/Contents/Resources/ghostty" "$DEST/GhosttyRuntime.app/Contents/Resources/"
cp "$SOURCE_APP/Contents/Info.plist" "$DEST/GhosttyRuntime.app/Contents/Info.plist"

cat > "$DEST/VERSION.txt" <<EOF
$VERSION
EOF

codesign --force --deep --sign - "$DEST/GhosttyRuntime.app" >/dev/null 2>&1 || true

echo "Vendored Ghostty $VERSION to $DEST"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SCHEME="${TAIRI_UI_TEST_SCHEME:-TairiUI}"
PROJECT="${TAIRI_UI_TEST_PROJECT:-$ROOT/TairiUI.xcodeproj}"
DERIVED_DATA_PATH="${TAIRI_UI_TEST_DERIVED_DATA:-$ROOT/.local/DerivedData/TairiUI}"
DESTINATION="${TAIRI_UI_TEST_DESTINATION:-platform=macOS}"
BUILD_APP="${TAIRI_UI_TEST_BUILD_APP:-1}"

export DEVELOPER_DIR
export TAIRI_APP_BUNDLE="${TAIRI_APP_BUNDLE:-$ROOT/dist/Tairi.app}"

if [[ "$BUILD_APP" == "1" ]]; then
  "$ROOT/scripts/build-app.sh"
elif [[ ! -d "$TAIRI_APP_BUNDLE" ]]; then
  echo "Missing app bundle: $TAIRI_APP_BUNDLE" >&2
  exit 1
fi

cd "$ROOT"
set +e
xcodebuild clean test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination "$DESTINATION"
status=$?
set -e

if [[ $status -ne 0 ]]; then
  cat >&2 <<'EOF'
UI tests failed.
If XCTest reports "Timed out while enabling automation mode", grant UI automation/accessibility permission to the runner environment in macOS System Settings, then retry `just test-ui`.
EOF
fi

exit "$status"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SCHEME="${TAIRI_UI_TEST_SCHEME:-TairiUI}"
PROJECT="${TAIRI_UI_TEST_PROJECT:-$ROOT/TairiUI.xcodeproj}"
DERIVED_DATA_PATH="${TAIRI_UI_TEST_DERIVED_DATA:-$ROOT/.local/DerivedData/TairiUI}"
SIGNING_IDENTITY="${TAIRI_UI_TEST_SIGNING_IDENTITY:-}"

export DEVELOPER_DIR
export TAIRI_APP_BUNDLE="${TAIRI_APP_BUNDLE:-$ROOT/dist/tairi.app}"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required to generate the UI test project. Install with: brew install xcodegen" >&2
  exit 1
fi

if [[ ! -d "$TAIRI_APP_BUNDLE" ]]; then
  "$ROOT/scripts/build-app.sh"
fi

xcodegen generate --spec "$ROOT/project.yml" --project "$ROOT" >/dev/null

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(
    security find-identity -v -p codesigning \
      | awk -F'"' '/Apple Development:/ { print $2; exit }'
  )"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "No Apple Development signing identity found for UI test runner." >&2
  exit 1
fi

rm -rf "$DERIVED_DATA_PATH"

cd "$ROOT"
xcodebuild build-for-testing \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination "platform=macOS"

RUNNER_APP="$DERIVED_DATA_PATH/Build/Products/Debug/TairiUITests-Runner.app"
HOST_APP="$DERIVED_DATA_PATH/Build/Products/Debug/UITestHost.app"

codesign --force --deep --sign "$SIGNING_IDENTITY" "$RUNNER_APP"
codesign --force --deep --sign "$SIGNING_IDENTITY" "$HOST_APP"

xcodebuild test-without-building \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination "platform=macOS" \
  -only-testing:TairiUITests/TairiUITests

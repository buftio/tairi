#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/release-config.sh"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required to validate the generated cask." >&2
  exit 1
fi

CASK_PATH="${1:-$ROOT/dist/release/homebrew/${TAIRI_APP_NAME}.rb}"
README_PATH="${2:-$ROOT/dist/release/homebrew/README.md}"
VALIDATION_TAP_NAME="${TAIRI_HOMEBREW_VALIDATION_TAP_NAME:-local/tairi-audit}"
TMP_ROOT="$ROOT/.local/tmp"

if [[ ! -f "$CASK_PATH" ]]; then
  echo "Cask not found: $CASK_PATH" >&2
  exit 1
fi

mkdir -p "$TMP_ROOT"
TMP_TAP_DIR="$(mktemp -d "$TMP_ROOT/homebrew-tap-validate.XXXXXX")"

cleanup() {
  brew untap "$VALIDATION_TAP_NAME" >/dev/null 2>&1 || true
  rm -rf "$TMP_TAP_DIR"
}
trap cleanup EXIT

mkdir -p "$TMP_TAP_DIR/Casks"
cp "$CASK_PATH" "$TMP_TAP_DIR/Casks/${TAIRI_APP_NAME}.rb"

if [[ -f "$README_PATH" ]]; then
  cp "$README_PATH" "$TMP_TAP_DIR/README.md"
fi

(
  cd "$TMP_TAP_DIR"
  git init -q
  git add .
  git -c user.name="tairi release bot" \
    -c user.email="releases@tairi.invalid" \
    commit -qm "Validate generated Homebrew tap"
)

brew untap "$VALIDATION_TAP_NAME" >/dev/null 2>&1 || true
HOMEBREW_NO_AUTO_UPDATE=1 brew tap --custom-remote "$VALIDATION_TAP_NAME" "$TMP_TAP_DIR" >/dev/null
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_FROM_API=1 brew style --cask "${VALIDATION_TAP_NAME}/${TAIRI_APP_NAME}"
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_FROM_API=1 brew audit --cask --strict "${VALIDATION_TAP_NAME}/${TAIRI_APP_NAME}"

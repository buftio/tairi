#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/release-config.sh"

APP_DIR="$ROOT/dist/${TAIRI_APP_BUNDLE_NAME}.app"
RELEASE_DIR="$ROOT/dist/release"
RELEASE_ARCH="${TAIRI_RELEASE_ARCH:-$(uname -m)}"
RELEASE_BASENAME="${TAIRI_APP_NAME}-${TAIRI_VERSION}-macos-${RELEASE_ARCH}"
ZIP_PATH="$RELEASE_DIR/${RELEASE_BASENAME}.app.zip"
DMG_PATH="$RELEASE_DIR/${RELEASE_BASENAME}.dmg"
CHECKSUMS_PATH="$RELEASE_DIR/${RELEASE_BASENAME}-checksums.txt"
HOMEBREW_DIR="$RELEASE_DIR/homebrew"
CASK_PATH="$HOMEBREW_DIR/${TAIRI_APP_NAME}.rb"
GITHUB_REPOSITORY_SLUG="${GITHUB_REPOSITORY:-buftio/tairi}"
GITHUB_RELEASE_URL="https://github.com/${GITHUB_REPOSITORY_SLUG}/releases/download/${TAIRI_RELEASE_TAG}/${RELEASE_BASENAME}.dmg"
NOTARY_TIMEOUT="${TAIRI_NOTARY_TIMEOUT:-20m}"
TMP_ROOT="$ROOT/.local/tmp"

mkdir -p "$TMP_ROOT"
WORK_DIR="$(mktemp -d "$TMP_ROOT/package-release.XXXXXX")"
STAGING_DIR="$WORK_DIR/dmg"
PRE_NOTARY_ZIP_PATH="$WORK_DIR/${RELEASE_BASENAME}-for-notary.zip"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

trash_path_if_present() {
  local path="$1"

  [[ -e "$path" ]] || return 0

  if ! command -v trash >/dev/null 2>&1; then
    echo "trash is required to replace existing release artifacts: $path" >&2
    exit 1
  fi

  trash "$path"
}

validate_notary_configuration() {
  local has_keychain_profile=0
  local has_api_key_path=0
  local has_key_id=0
  local has_issuer=0

  [[ -n "${TAIRI_NOTARY_KEYCHAIN_PROFILE:-}" ]] && has_keychain_profile=1
  [[ -n "${TAIRI_NOTARY_API_KEY_PATH:-}" ]] && has_api_key_path=1
  [[ -n "${TAIRI_NOTARY_KEY_ID:-}" ]] && has_key_id=1
  [[ -n "${TAIRI_NOTARY_ISSUER:-}" ]] && has_issuer=1

  if (( has_keychain_profile )) && (( has_api_key_path || has_key_id || has_issuer )); then
    echo "Configure notarization with either TAIRI_NOTARY_KEYCHAIN_PROFILE or App Store Connect API key variables, not both." >&2
    exit 1
  fi

  if (( has_api_key_path != has_key_id )); then
    echo "TAIRI_NOTARY_API_KEY_PATH and TAIRI_NOTARY_KEY_ID must be set together for notarization." >&2
    exit 1
  fi

  if (( has_issuer )) && ! (( has_api_key_path && has_key_id )); then
    echo "TAIRI_NOTARY_ISSUER requires TAIRI_NOTARY_API_KEY_PATH and TAIRI_NOTARY_KEY_ID." >&2
    exit 1
  fi
}

notary_mode() {
  if [[ -n "${TAIRI_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    echo "keychain-profile"
    return 0
  fi

  if [[ -n "${TAIRI_NOTARY_API_KEY_PATH:-}" && -n "${TAIRI_NOTARY_KEY_ID:-}" ]]; then
    echo "api-key"
    return 0
  fi

  echo "none"
}

maybe_notarize() {
  local path="$1"
  local mode

  mode="$(notary_mode)"

  if [[ "$mode" == "keychain-profile" ]]; then
    xcrun notarytool submit \
      "$path" \
      --keychain-profile "$TAIRI_NOTARY_KEYCHAIN_PROFILE" \
      --wait \
      --timeout "$NOTARY_TIMEOUT"
    return 0
  fi

  if [[ "$mode" == "api-key" ]]; then
    local -a args=(
      --key "$TAIRI_NOTARY_API_KEY_PATH"
      --key-id "$TAIRI_NOTARY_KEY_ID"
    )
    if [[ -n "${TAIRI_NOTARY_ISSUER:-}" ]]; then
      args+=(--issuer "$TAIRI_NOTARY_ISSUER")
    fi

    xcrun notarytool submit "$path" "${args[@]}" --wait --timeout "$NOTARY_TIMEOUT"
    return 0
  fi

  echo "Skipping notarization for $path; no notary credentials configured." >&2
  return 1
}

maybe_staple() {
  local path="$1"
  xcrun stapler staple "$path"
  xcrun stapler validate "$path"
}

maybe_sign_dmg() {
  local path="$1"

  if [[ "${TAIRI_CODESIGN_IDENTITY:--}" == "-" ]]; then
    return 0
  fi

  codesign --force --timestamp --sign "$TAIRI_CODESIGN_IDENTITY" "$path"
  codesign --verify --verbose=2 "$path"
}

validate_notary_configuration
mkdir -p "$RELEASE_DIR" "$HOMEBREW_DIR"
trash_path_if_present "$ZIP_PATH"
trash_path_if_present "$DMG_PATH"
trash_path_if_present "$CHECKSUMS_PATH"
trash_path_if_present "$CASK_PATH"

"$ROOT/scripts/build-app.sh"

ditto -c -k --keepParent "$APP_DIR" "$PRE_NOTARY_ZIP_PATH"
if maybe_notarize "$PRE_NOTARY_ZIP_PATH"; then
  maybe_staple "$APP_DIR"
fi

ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

mkdir -p "$STAGING_DIR"
ditto "$APP_DIR" "$STAGING_DIR/${TAIRI_APP_BUNDLE_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$TAIRI_APP_BUNDLE_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs APFS \
  -format UDZO \
  -ov \
  "$DMG_PATH" >/dev/null

maybe_sign_dmg "$DMG_PATH"
if maybe_notarize "$DMG_PATH"; then
  maybe_staple "$DMG_PATH"
fi

shasum -a 256 "$ZIP_PATH" "$DMG_PATH" > "$CHECKSUMS_PATH"
"$ROOT/scripts/generate-homebrew-cask.sh" "$GITHUB_RELEASE_URL" "$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')" "$CASK_PATH"

echo "Created:"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
echo "  $CHECKSUMS_PATH"
echo "  $CASK_PATH"

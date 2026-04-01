#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/release-config.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <download-url> <sha256> [output-path]
EOF
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage >&2
  exit 1
fi

DOWNLOAD_URL="$1"
SHA256="$2"
OUTPUT_PATH="${3:-/dev/stdout}"
CASK_URL="$DOWNLOAD_URL"
RELEASE_TAG_TEMPLATE='v#{version}'
VERSION_TEMPLATE='#{version}'

CASK_URL="${CASK_URL//${TAIRI_RELEASE_TAG}/${RELEASE_TAG_TEMPLATE}}"
CASK_URL="${CASK_URL//${TAIRI_VERSION}/${VERSION_TEMPLATE}}"

mkdir -p "$(dirname "$OUTPUT_PATH")"

cat > "$OUTPUT_PATH" <<EOF
cask "${TAIRI_APP_NAME}" do
  version "${TAIRI_VERSION}"
  sha256 "${SHA256}"

  url "${CASK_URL}"
  name "${TAIRI_APP_BUNDLE_NAME}"
  desc "Minimal workspace app inspired by Niri's scrolling philosophy"
  homepage "${TAIRI_HOMEPAGE_URL}"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: "${TAIRI_HOMEBREW_MIN_MACOS}"

  app "${TAIRI_APP_BUNDLE_NAME}.app"

  zap trash: [
    "~/Library/Logs/${TAIRI_APP_NAME}",
    "~/Library/Preferences/${TAIRI_BUNDLE_ID}.plist",
  ]
end
EOF

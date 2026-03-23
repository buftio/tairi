#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/release-config.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [tap-repository] [output-path]
EOF
}

if [[ $# -gt 2 ]]; then
  usage >&2
  exit 1
fi

TAP_REPOSITORY="${1:-$TAIRI_HOMEBREW_TAP_REPOSITORY_DEFAULT}"
OUTPUT_PATH="${2:-/dev/stdout}"
TAP_NAME="$(homebrew_tap_name_for_repository "$TAP_REPOSITORY")"

mkdir -p "$(dirname "$OUTPUT_PATH")"

cat > "$OUTPUT_PATH" <<EOF
# Homebrew Tap for ${TAIRI_APP_NAME}

Install:

\`\`\`sh
brew tap ${TAP_NAME}
brew install --cask ${TAIRI_APP_NAME}
\`\`\`

Upgrade:

\`\`\`sh
brew upgrade --cask ${TAIRI_APP_NAME}
\`\`\`

This tap publishes the Homebrew cask for [${TAIRI_APP_NAME}](${TAIRI_HOMEPAGE_URL}).
Releases are sourced from GitHub Releases in the main app repository.

Current requirements:

- Apple Silicon
- macOS ${TAIRI_MIN_MACOS} or newer

The cask is generated from the release automation in the main repository.
EOF

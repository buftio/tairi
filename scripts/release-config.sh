#!/usr/bin/env bash

export TAIRI_APP_NAME="tairi"
export TAIRI_BUNDLE_ID="org.tairi.app"
export TAIRI_VERSION="0.9.0"
export TAIRI_BUILD_NUMBER="1"
export TAIRI_MIN_MACOS="14.0"
export TAIRI_HOMEPAGE_URL="https://github.com/buftio/tairi"
export TAIRI_RELEASE_TAG="v${TAIRI_VERSION}"
export TAIRI_HOMEBREW_TAP_REPOSITORY_DEFAULT="buftio/homebrew-tap"

homebrew_macos_floor_for_version() {
  local major="${1%%.*}"

  case "$major" in
    13) echo ">= :ventura" ;;
    14) echo ">= :sonoma" ;;
    15) echo ">= :sequoia" ;;
    *)
      echo "Unsupported TAIRI_MIN_MACOS major version for Homebrew cask generation: $1" >&2
      return 1
      ;;
  esac
}

export TAIRI_HOMEBREW_MIN_MACOS="$(homebrew_macos_floor_for_version "$TAIRI_MIN_MACOS")"

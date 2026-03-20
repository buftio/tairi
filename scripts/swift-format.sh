#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="$ROOT_DIR/.swift-format"
TARGETS=(
  "$ROOT_DIR/Package.swift"
  "$ROOT_DIR/Sources"
  "$ROOT_DIR/Tests"
  "$ROOT_DIR/UITestHost"
)

mode="${1:-}"

case "$mode" in
  format)
    exec swift format format \
      --configuration "$CONFIG_PATH" \
      --in-place \
      --parallel \
      --recursive \
      "${TARGETS[@]}"
    ;;
  lint)
    exec swift format lint \
      --configuration "$CONFIG_PATH" \
      --strict \
      --parallel \
      --recursive \
      "${TARGETS[@]}"
    ;;
  *)
    echo "usage: $0 <format|lint>" >&2
    exit 64
    ;;
esac

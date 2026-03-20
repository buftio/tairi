set shell := ["zsh", "-cu"]

default:
  just --list

build:
  swift build

dev *args:
  ./scripts/ensure-ghostty.sh >/dev/null
  swift run tairi {{args}}

dev-shell-diagnose:
  ./scripts/ensure-ghostty.sh >/dev/null
  env TAIRI_TERMINAL_DIAG=1 swift run tairi

vendor-ghostty:
  ./scripts/vendor-ghostty.sh

bundle:
  ./scripts/build-app.sh

release-artifacts:
  ./scripts/package-release.sh

install target="":
  if [[ -n "{{target}}" ]]; then ./scripts/install-app.sh "{{target}}"; else ./scripts/install-app.sh; fi

open:
  open dist/tairi.app

bundle-open:
  just bundle
  just open

alias app := bundle-open

clean-dist:
  if [[ -d dist/tairi.app ]]; then trash dist/tairi.app; fi

rebuild-app:
  just clean-dist
  just bundle

diagnose-claude mode="plain":
  if [[ "{{mode}}" == "with-cmux-hooks" ]]; then ./scripts/diagnose-claude.sh --with-cmux-hooks; else ./scripts/diagnose-claude.sh --without-hooks; fi

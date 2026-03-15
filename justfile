set shell := ["zsh", "-cu"]

default:
  just --list

build:
  swift build

dev:
  swift run tairi

vendor-ghostty source="/Applications/Ghostty.app":
  ./scripts/vendor-ghostty.sh "{{source}}"

bundle:
  ./scripts/build-app.sh

install-app target="":
  if [[ -n "{{target}}" ]]; then ./scripts/install-app.sh "{{target}}"; else ./scripts/install-app.sh; fi

open-app:
  open dist/tairi.app

bundle-open:
  just bundle
  just open-app

alias app := bundle-open
alias install := install-app

clean-dist:
  if [[ -d dist/tairi.app ]]; then trash dist/tairi.app; fi

rebuild-app:
  just clean-dist
  just bundle

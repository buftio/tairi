#!/usr/bin/env zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
log_root="$repo_root/.local/logs/shell-diagnose"
mkdir -p "$log_root"

timestamp="$(date +"%Y%m%d-%H%M%S")"
tty_name="none"
if [[ -t 0 ]]; then
  tty_name="$(tty | sed 's#^/dev/##; s#[^A-Za-z0-9._-]#_#g')"
fi

log_file="$log_root/${timestamp}-$$-${tty_name}.log"
shell_bin="${TAIRI_TERMINAL_DIAG_SHELL:-${SHELL:-/bin/zsh}}"

{
  echo "started_at=$(date -Iseconds)"
  echo "pid=$$"
  echo "ppid=$PPID"
  echo "pwd=$PWD"
  echo "tty=$tty_name"
  echo "shell_bin=$shell_bin"
  echo "argv0=$0"
  echo "path=$PATH"
  env | sort | grep -E '^(TERM|TERM_PROGRAM|SHELL|ZDOTDIR|CLAUDE|GHOSTTY|TAIRI)=' || true
} >> "$log_file"

trap 'echo "signal=HUP at=$(date -Iseconds)" >> "$log_file"' HUP
trap 'echo "signal=INT at=$(date -Iseconds)" >> "$log_file"' INT
trap 'echo "signal=QUIT at=$(date -Iseconds)" >> "$log_file"' QUIT
trap 'echo "signal=TERM at=$(date -Iseconds)" >> "$log_file"' TERM

set +e
"$shell_bin"
rc=$?
set -e

{
  echo "shell_exit_code=$rc"
  echo "finished_at=$(date -Iseconds)"
} >> "$log_file"

exit "$rc"

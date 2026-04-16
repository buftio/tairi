#!/usr/bin/env zsh

set -euo pipefail

pid_file="${1:?}"
command_string="${2:-${SHELL:-/bin/zsh}}"

mkdir -p "$(dirname "$pid_file")"
printf '%s\n' "$$" >| "$pid_file"

cleanup() {
  rm -f "$pid_file"
}

trap cleanup EXIT

if [[ "$command_string" == direct:* ]]; then
  command_string="${command_string#direct:}"
  argv=(${(z)command_string})
  exec "${argv[@]}"
fi

if [[ "$command_string" == shell:* ]]; then
  exec /bin/sh -lc "${command_string#shell:}"
fi

if [[ "$command_string" == *[[:space:]]* ]]; then
  exec /bin/sh -lc "$command_string"
fi

exec "$command_string"

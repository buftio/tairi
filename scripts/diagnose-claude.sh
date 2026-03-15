#!/usr/bin/env zsh

set -euo pipefail

mode="plain"
declare -a passthrough_args=()

while (( $# > 0 )); do
  case "$1" in
    --with-cmux-hooks)
      mode="with-cmux-hooks"
      shift
      ;;
    --without-hooks)
      mode="plain"
      shift
      ;;
    --)
      shift
      passthrough_args=("$@")
      break
      ;;
    *)
      passthrough_args+=("$1")
      shift
      ;;
  esac
done

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
log_root="$repo_root/.local/logs/claude-diagnose"
timestamp="$(date +"%Y%m%d-%H%M%S")"
run_dir="$log_root/$timestamp"

mkdir -p "$run_dir"

claude_bin="${CLAUDE_BIN:-$(command -v claude || true)}"
if [[ -z "$claude_bin" ]]; then
  echo "claude not found on PATH" >&2
  exit 1
fi

cmux_bin=""
if command -v cmux >/dev/null 2>&1; then
  cmux_bin="$(command -v cmux)"
elif [[ -x /Applications/cmux.app/Contents/MacOS/cmux ]]; then
  cmux_bin="/Applications/cmux.app/Contents/MacOS/cmux"
fi

debug_file="$run_dir/claude-debug.log"
transcript_file="$run_dir/terminal.typescript"
child_status_file="$run_dir/child-status.log"
hooks_file="$run_dir/hooks.json"
child_script="$run_dir/run-child.zsh"

cat > "$hooks_file" <<EOF
{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"cmux claude-hook session-start","timeout":10}]}],"Stop":[{"matcher":"","hooks":[{"type":"command","command":"cmux claude-hook stop","timeout":10}]}],"Notification":[{"matcher":"","hooks":[{"type":"command","command":"cmux claude-hook notification","timeout":10}]}]}}
EOF

{
  echo "timestamp=$timestamp"
  echo "repo_root=$repo_root"
  echo "pwd=$PWD"
  echo "mode=$mode"
  echo "claude_bin=$claude_bin"
  echo "cmux_bin=${cmux_bin:-missing}"
  if [[ -t 0 ]]; then
    echo "tty=$(tty)"
  else
    echo "tty=none"
  fi
  echo "shell=${SHELL:-unknown}"
  echo "os=$(sw_vers -productVersion 2>/dev/null || echo unknown)"
  echo "claude_version=$("$claude_bin" --version 2>/dev/null || echo unknown)"
} > "$run_dir/meta.txt"

env | sort > "$run_dir/env.txt"
ulimit -a > "$run_dir/ulimit.txt" 2>&1 || true
ps -axo pid,ppid,tty,stat,start,time,command | grep -E "claude|cmux|tairi|ghostty" > "$run_dir/processes.txt" || true

cat > "$child_script" <<EOF
#!/usr/bin/env zsh
set -euo pipefail

status_file="$child_status_file"
debug_file="$debug_file"
hooks_file="$hooks_file"
claude_bin="$claude_bin"
mode="$mode"

{
  echo "started_at=\$(date -Iseconds)"
  echo "pwd=\$PWD"
  if [[ -t 0 ]]; then
    echo "tty=\$(tty)"
  else
    echo "tty=none"
  fi
  echo "pid=\$\$"
  echo "ppid=\$PPID"
  echo "path=\$PATH"
} >> "\$status_file"

trap 'echo "signal=HUP at=\$(date -Iseconds)" >> "\$status_file"' HUP
trap 'echo "signal=INT at=\$(date -Iseconds)" >> "\$status_file"' INT
trap 'echo "signal=QUIT at=\$(date -Iseconds)" >> "\$status_file"' QUIT
trap 'echo "signal=TERM at=\$(date -Iseconds)" >> "\$status_file"' TERM
trap 'echo "signal=ABRT at=\$(date -Iseconds)" >> "\$status_file"' ABRT

typeset -a cmd
cmd=("\$claude_bin" "--debug-file" "\$debug_file")
if [[ "\$mode" == "with-cmux-hooks" ]]; then
  cmd+=("--settings" "\$(cat "\$hooks_file")")
fi
if (( \$# > 0 )); then
  cmd+=("\$@")
fi

printf 'command=' >> "\$status_file"
printf '%q ' "\${cmd[@]}" >> "\$status_file"
printf '\n' >> "\$status_file"

set +e
"\${cmd[@]}"
rc=\$?
set -e

{
  echo "exit_code=\$rc"
  echo "finished_at=\$(date -Iseconds)"
} >> "\$status_file"

exit \$rc
EOF

chmod +x "$child_script"

echo "Claude diagnostics will be written to: $run_dir"
if [[ "$mode" == "with-cmux-hooks" && -z "$cmux_bin" ]]; then
  echo "Warning: cmux is not on PATH in this shell. Repro from Tairi may differ." >&2
fi

set +e
/usr/bin/script -q "$transcript_file" "$child_script" "${passthrough_args[@]}"
rc=$?
set -e

{
  echo "wrapper_exit_code=$rc"
  echo "wrapper_finished_at=$(date -Iseconds)"
} >> "$run_dir/meta.txt"

echo "Transcript: $transcript_file"
echo "Claude debug: $debug_file"
echo "Status: $child_status_file"
exit "$rc"

# Logs

## Main files

- App log: `.local/logs/tairi.log` in a repo checkout, or `~/Library/Logs/tairi/tairi.log` in the packaged app
- Crash reports from the previous unexpected launch: `.local/logs/crash-reports/*.md` in a repo checkout, or `~/Library/Logs/tairi/crash-reports/*.md` in the packaged app
- macOS native crash dumps: `$HOME/Library/Logs/DiagnosticReports/tairi-*.ips`

## What they mean

- `tairi.log` is the first place to look for app lifecycle and Ghostty runtime activity.
- The Markdown crash report is a repo-local summary written on the next launch after an unexpected exit.
- The macOS `.ips` report is the strongest signal when the OS recorded a native crash.

## Normal shutdown vs unexpected exit

- `application terminated cleanly` in `tairi.log` means the normal shutdown path ran.
- If that line is missing, prefer the newest Markdown crash report over guessing.
- If a Markdown crash report says `unexpected termination without a clean shutdown marker` and there is no new matching `.ips`, the app disappeared without a normal crash record.
- That marker-only case can happen after `pkill`, force-quit, or replacing the running app during local verification.

## Repro targets

- Local dev: `just dev`
- Packaged app: `just bundle` then `open -na dist/Tairi.app`

## When to prefer each

- Use local dev for faster repro loops and debugger attach.
- Use the packaged app when the bug may depend on bundle layout, embedded runtime, or codesigning.

In the packaged app, `Help > Export Diagnostics Bundle...` creates a zip with the current log plus the available crash reports and native crash dumps.

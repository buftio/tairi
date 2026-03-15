# Crash Diagnostics

## Collect in order

1. Newest `.local/logs/crash-reports/*.md`
2. Newest `~/Library/Logs/DiagnosticReports/tairi-*.ips` for the same time, if one exists
3. Last ~150 lines of `.local/logs/tairi.log`

## Triage order

1. Read the Markdown crash report first.
2. If there is a matching `.ips`, use that as the native-crash source of truth.
3. Use `tairi.log` to reconstruct the app and Ghostty lifecycle around the failure.

## Current Ghostty instrumentation

The app now logs these lifecycle markers in `tairi.log`:

- `ghostty creating app ... context=...`
- `ghostty app created ... app=...`
- `ghostty surface ... init complete ... surface=...`
- `ghostty surface ... did move superview ...`
- `ghostty surface ... will move window ...`
- `ghostty surface ... did move to window ...`
- `ghostty surface ... syncDisplayID ...`
- `ghostty wakeup ... count=...`
- `ghostty disposing ...`
- `ghostty freeing app ...`
- `ghostty releasing context ...`

## How to read the lifecycle

- If logs stop before `did move to window`, the failure is likely during early surface or view setup.
- If logs stop after window attach but before later wakeups, the failure is likely in first render or startup callbacks.
- If logs reach dispose/freeing lines, the failure may be teardown or lifetime related.
- Pointer values for `context`, `app`, `surface`, and `view` help correlate which native object was active when the failure happened.

## Known noisy lines

Do not treat these as the primary crash signal unless they line up with a real native crash:

- Ghostty `compose failure` spam
- AppKit/libxpc state-restoration assertion noise

## Practical commands

```sh
tail -n 150 .local/logs/tairi.log
ls -1t .local/logs/crash-reports/*.md | head
ls -1t ~/Library/Logs/DiagnosticReports/tairi-*.ips | head
```

## Good report bundle

When sharing a repro, include:

- the newest Markdown crash report
- the matching `.ips`, if present
- the relevant `tairi.log` tail
- whether it happened in `just dev` or the packaged app

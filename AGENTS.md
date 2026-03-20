# Tairi

## Terminology

- `window`: the app window that contains everything.
- `tile`: a single content tile, such as a Ghostty terminal.
- `strip`: a horizontal line of tiles, also known as a workspace.

## Docs

- Treat `docs/` as an important source of truth before changing behavior.
- Start with:
  - [docs/ghostty.md](docs/ghostty.md)
  - [docs/logs.md](docs/logs.md)
  - [docs/crash-diagnostics.md](docs/crash-diagnostics.md)
  - [docs/ui-testing.md](docs/ui-testing.md)

## Dev Hints

- dev app: `just dev`
- to command the dev app via AppleScript/System Events, target the `debug/tairi` PID, not `tell application "tairi"`:
  `pgrep -n -f 'debug/tairi'`

## Runtime Source

- Development uses cached Ghostty from `.local/vendor/Ghostty/...`

## Ghostty

- Read [docs/ghostty.md](docs/ghostty.md) before changing terminal/session behavior.
- For app chrome colors, start with [Sources/TairiApp/GhosttyAppTheme.swift](Sources/TairiApp/GhosttyAppTheme.swift).
- Tairi uses first-class in-process Ghostty sessions; tile host views attach/detach from persistent session-owned surface views.
- Explicit tile close is destructive and should terminate the session before removing the tile.
- UI churn such as workspace switching or host view rebuilds should detach, not terminate, the session.

## Logs

- Repo-local log file: `.local/logs/tairi.log`
- Crash reports from the previous unexpected launch: `.local/logs/crash-reports/*.md`
- macOS native crash dumps: `~/Library/Logs/DiagnosticReports/tairi-*.ips`
- Full guide: [docs/logs.md](docs/logs.md)

## Crash Diagnosis

- Check the Markdown crash report first, then the matching `.ips`, then `tairi.log`.
- Full guide: [docs/crash-diagnostics.md](docs/crash-diagnostics.md)

## UI Testing

- Keep accessibility identifiers stable and prefer visible-behavior XCUITests.
- Full guide: [docs/ui-testing.md](docs/ui-testing.md)

## Keyboard Shortcuts

- Keep app shortcuts in a single source of truth: [Sources/TairiApp/TairiHotkeys.swift](Sources/TairiApp/TairiHotkeys.swift).
- UI hints, menu bindings, and event matching should derive from that file rather than hardcoding key combos in multiple places.

## Animations

- Keep animation speed and enable/disable behavior in the shared policy, not per-view constants.
- Start with [Sources/TairiApp/AppAnimation.swift](Sources/TairiApp/AppAnimation.swift) and [Sources/TairiApp/AppSettings.swift](Sources/TairiApp/AppSettings.swift) before changing motion behavior.
- App-owned animations should respect the centralized policy, including UI test mode and macOS Reduce Motion.

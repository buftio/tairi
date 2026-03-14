# Tairi

## Dev Hints

- dev app: `just dev`

## Runtime Source

- Development uses vendored Ghostty from `Vendor/Ghostty/...`

## Logs

- Repo-local log file: `.local/logs/tairi.log`

## UI Testing

- Keep accessibility identifiers stable for user-facing controls and custom AppKit views; add them with new UI.
- Prefer asserting visible behavior with XCUITest; do not use it for Ghostty internals.
- For custom canvas/tile changes, keep AX labels meaningful enough for Accessibility Inspector.
- For quick live automation, launch the built app with `open -na dist/tairi.app`, then drive it via `osascript` and `System Events`.
- Click the terminal surface before typing. Activating `tairi` alone is not enough to reliably send text into Ghostty; for multi-tile flows, click the specific tile you want first.
- If the app seems to "close" after a terminal exits, check `~/Library/Logs/DiagnosticReports/tairi-*.ips` as well as `.local/logs/tairi.log`; it may be a crash disguised as a window-close bug.
- To type a terminal command end to end, activate `tairi`, send keystrokes, then press Enter:

```sh
open -na dist/tairi.app
osascript <<'APPLESCRIPT'
tell application "tairi" to activate
delay 1
tell application "System Events"
  keystroke "echo tairi-e2e > /tmp/tairi-e2e.txt"
  key code 36
end tell
APPLESCRIPT
cat /tmp/tairi-e2e.txt
```

# cmux

cmux is oss app which as well it's loated in ~/p/oss/cmux
consult with it's source in

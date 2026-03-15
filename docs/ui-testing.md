# UI Testing

## General guidance

- Keep accessibility identifiers stable for user-facing controls and custom AppKit views.
- Prefer asserting visible behavior with XCUITest.
- Do not use XCUITest for Ghostty internals.
- For custom canvas or tile changes, keep AX labels meaningful enough for Accessibility Inspector.

## Live automation

- Launch the built app with `open -na dist/tairi.app`.
- Drive it with `osascript` and `System Events`.
- Click the terminal surface before typing.
- Activating `tairi` alone is not enough to reliably send text into Ghostty.
- For multi-tile flows, click the specific tile you want first.

## Crash-shaped behavior

- If the app seems to "close" after a terminal exits, it may be a crash disguised as a window-close bug.
- In that case, follow the crash workflow in [crash-diagnostics.md](crash-diagnostics.md).

## Practical command

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

# UI Testing

## General guidance

- Keep accessibility identifiers stable for user-facing controls and custom AppKit views.
- Prefer asserting visible behavior with XCUITest.
- Do not use XCUITest for Ghostty internals.
- For custom canvas or tile changes, keep AX labels meaningful enough for Accessibility Inspector.
- Run the checked-in UI suite with `just test-ui`.
- `just test-ui` builds `dist/tairi.app` first, then runs `xcodebuild` against the shared `TairiUI` scheme.
- If XCTest reports `Timed out while enabling automation mode`, re-run after granting UI automation/accessibility permission to the runner environment in macOS System Settings.

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
just test-ui
```

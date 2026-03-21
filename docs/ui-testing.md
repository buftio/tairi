# UI Testing

## General guidance

- Keep accessibility identifiers stable for user-facing controls and custom AppKit views.
- Prefer asserting visible behavior with XCUITest.
- Do not use XCUITest for Ghostty internals.
- For custom canvas or tile changes, keep AX labels meaningful enough for Accessibility Inspector.
- Run the checked-in UI suite with `just test-ui`.
- `just test-ui` builds `dist/tairi.app` first, then runs `xcodebuild` against the shared `TairiUI` scheme.
- The UI runner is expected to be locally signed. If macOS says `TairiUITests-Runner.app` is damaged, re-check the project signing setup instead of working around Gatekeeper by hand.
- If XCTest reports `Timed out while enabling automation mode`, re-run after granting UI automation/accessibility permission to the runner environment in macOS System Settings.

## Practical findings

- Do not assume a pristine startup state in UI tests. Workspace and tile persistence can survive across launches, so assertions should tolerate existing state unless the test explicitly resets it.
- On macOS, accessibility identifiers can surface under different roles than expected. Prefer identifier-based or role-agnostic queries over assuming a control will always appear as `button`, `group`, `otherElement`, or `staticText`.
- Prefer behavior assertions over exact layout math. Tests that depend on pixel gaps, strict element counts, or narrow geometry thresholds have been much more brittle than tests that verify rename, selection, overflow visibility, or resize behavior.
- If a query finds multiple AX nodes for what looks like one logical control, prefer using visible/bound elements rather than raw query counts.
- Spotlight and overview flows are especially sensitive to AX exposure on macOS. Add coverage there only when the interaction can be located through stable identifiers and verified through durable user-visible behavior.

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

# Ghostty Setup

This repo embeds Ghostty as a native runtime and hosts each terminal inside an AppKit `NSView`.

## Runtime Layout

Development uses the vendored runtime under:

- `Vendor/Ghostty/...`

Bundled app builds place the runtime at:

- `tairi.app/Contents/Frameworks/GhosttyRuntime.app`
- `tairi.app/Contents/Resources/ghostty`

There is no fallback to a system-installed `/Applications/Ghostty.app`.

## Bootstrap Flow

Startup happens in [GhosttyRuntime.swift](../Sources/TairiApp/GhosttyRuntime.swift):

1. `configureBundledGhosttyPaths()` sets:
   - `GHOSTTY_RESOURCES_DIR`
   - `TAIRI_BUNDLED_GHOSTTY_BIN`
2. `tairi_ghostty_load(nil)` loads the dynamic runtime.
3. `GhosttyRuntimeCompatibility.validateLoadedRuntime()` verifies the loaded runtime matches the vendored headers/version expectations.
4. `tairi_ghostty_init(...)` initializes Ghostty for the process.
5. App focus and termination observers are installed.

The dynamic symbol wrapper lives in:

- [GhosttyDyn.c](../Sources/GhosttyDyn/GhosttyDyn.c)
- [GhosttyDyn.h](../Sources/GhosttyDyn/include/GhosttyDyn.h)

## Session Model

Tairi now separates terminal session lifetime from tile host view lifetime.

Main types:

- [WorkspaceStore.swift](../Sources/TairiApp/WorkspaceStore.swift)
  - each terminal tile stores `surface.terminalSessionID`
- [GhosttySession.swift](../Sources/TairiApp/GhosttySession.swift)
  - owns a session record
- [GhosttySessionRegistry.swift](../Sources/TairiApp/GhosttySessionRegistry.swift)
  - maps session IDs and tile IDs
- [GhosttySurfaceView.swift](../Sources/TairiApp/GhosttySurfaceView.swift)
  - persistent native view for a session

Ownership boundary:

- tile = placement and UI identity
- session = Ghostty app/surface/lifecycle
- host view = temporary attachment point

This means a session can survive:

- workspace switching
- tile host view teardown/rebuild
- layout churn
- focus changes

But it does not survive:

- explicit tile close
- app termination

## Tile Lifecycle

### Create

1. UI calls `GhosttyRuntime.createTile(...)`.
2. Runtime creates a `sessionID`.
3. Store creates a tile bound to that `sessionID`.
4. [WorkspaceTileHostView.swift](../Sources/TairiApp/WorkspaceTileHostView.swift) attaches the session view to its surface container.

### UI Churn

When a tile host view disappears because of view churn, it calls:

- `runtime.detachTile(tileID, reason: .uiChurn)`

That removes the `NSView` from the hierarchy but keeps the Ghostty session alive.

When the tile host returns, it calls:

- `runtime.attachTile(tileID, to: containerView)`

and reuses the same live session view.

### Explicit Close

The red traffic-light button in the tile header calls:

- `runtime.closeTile(tileID)`

That does:

1. terminate the session
2. free the Ghostty app/surface
3. remove the tile from the store

This is intentionally destructive.

## Ghostty Callbacks

Ghostty runtime callbacks are split into:

- [GhosttyRuntimeSessions.swift](../Sources/TairiApp/GhosttyRuntimeSessions.swift)
- [GhosttyRuntimeCallbacks.swift](../Sources/TairiApp/GhosttyRuntimeCallbacks.swift)

Key callbacks:

- `wakeup`
- `action`
- `readClipboard`
- `confirmReadClipboard`
- `writeClipboard`
- `closeSurface`

Actions are decoded in [GhosttyActionAdapter.swift](../Sources/TairiApp/GhosttyActionAdapter.swift) into session-centric events such as:

- title updates
- pwd updates
- new split/new tab requests
- child exit
- command finished

## Exit Behavior

User-configurable exit behavior lives in [AppSettings.swift](../Sources/TairiApp/AppSettings.swift):

- `closeImmediately`
- `waitForKeyPress`

The runtime applies this through Ghostty config overrides:

- `wait-after-command`
- `quit-after-last-window-closed = false`

If a session exits while detached, Tairi garbage-collects it immediately.

If it exits while attached, Tairi first records the child exit and waits for
Ghostty `close_surface` to confirm the surface is done.

Auto-close for an attached tile is also gated on recent user input:

- the exiting tile must still own the most recent input
- that input must be no older than ~2 seconds

If that gate does not pass, the exited tile can remain visible instead of being
closed automatically.

## Logging

Ghostty activity is logged to:

- `.local/logs/tairi.log`

Useful log categories include:

- session created
- session attached
- session detached
- child exited
- close surface
- freeing app
- releasing context

For crash-focused guidance, see [crash-diagnostics.md](crash-diagnostics.md).

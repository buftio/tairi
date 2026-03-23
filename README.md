# tairi

A scrollable, spatial terminal workspace.

Inspired by scrollable tiling window managers like niri

- sessions don't shrink
- everything stays visible
- built for multi-project / multi-process workflows

## Install

Install the published app from Homebrew:

```sh
brew tap buftio/tap
brew install --cask tairi
```

## UI

`strip` is the main horizontal workspace row of tiles:

![Strip view](docs/screenshots/strip1.gif)

Navigate with trackpad swipes or `⌥⌘` + arrow keys:

- `⌥⌘←` and `⌥⌘→` move between tiles
- `⌥⌘↑` and `⌥⌘↓` move between strips

`zoom-out` pulls the current window into an overview so you can scan strips and tiles at once:

![Zoomed-out overview](docs/screenshots/zoom-out.png)

Pinch out to enter zoom-out overview.

For a quick tour of the rest of the UI, see [docs/ui-walkthrough.md](docs/ui-walkthrough.md).

## Who is this for?

Developers running multiple services, agents, or logs who want a spatial, always-visible workflow.

## Why not tmux?

tmux forces you to divide a fixed screen into smaller panes.

tairi removes that constraint entirely. Your workspace expands horizontally instead.

## Prerequisites

For running Tairi from source:

- macOS 14 or newer
- Xcode with Swift 6 toolchains available on the command line
- [just](https://github.com/casey/just)
- `trash`

Optional:

- `xcodegen` for UI tests
- an Apple Development signing identity for the UI test runner

## Quick Start

From a fresh clone:

```sh
just dev
```

`just dev` automatically downloads the pinned Ghostty runtime declared in
[Vendor/ghostty-runtime.env](Vendor/ghostty-runtime.env) into the local cache
under `.local/vendor/Ghostty/...`.

Expected result:

- the app launches
- one window opens
- the first terminal tile is backed by the vendored Ghostty runtime

Custom startup strips can be passed through to the dev app:

```sh
just dev --strip 1,1,1 --strip 0.5,1
```

## Packaging

Build a distributable bundle:

```sh
just bundle
```

Build and install into your user Applications folder:

```sh
just install
```

`just install` updates the existing installed copy if one already exists.
It also ensures the manifest-pinned Ghostty runtime is cached before building.

The bundled runtime is baked in app.
Development uses the cached runtime under `.local/vendor/Ghostty/...`.

## Contributing

For day-to-day development, the main loop is:

```sh
just dev
```

Gate:

```sh
just format && just lint && swift test
```

UI tests currently require extra local setup:

- `xcodegen` installed
- a working Apple Development signing identity

Run them with:

```sh
./scripts/test-ui.sh
```

Auxiliary diagnostics and CI helper scripts live under `scripts/misc/`.

Common first-run issues:

- the pinned Ghostty download may fail if it cannot be fetched
- `just install` expects `trash` to be installed
- UI tests fail without a local signing identity

## License

Tairi is available under the MIT license. See [LICENSE](LICENSE).

## Third-Party Software

Tairi vendors and redistributes Ghostty as its terminal runtime, including
Sparkle as bundled inside the copied Ghostty app runtime layout.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for details.
Built app bundles also include the notice set under
`Contents/Resources/ThirdPartyNotices/`.

## Docs

- [Ghostty setup](docs/ghostty.md)
- [Logs](docs/logs.md)
- [Crash diagnostics](docs/crash-diagnostics.md)
- [Release packaging and distribution](docs/release.md)
- [UI testing](docs/ui-testing.md)
- [UI walkthrough](docs/ui-walkthrough.md)

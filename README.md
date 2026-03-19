# tairi

Minimal workspace app inspired by Niri's scrolling philosophy:

- vertical dynamic workspaces
- horizontal strip
- new terminals append as columns instead of resizing existing ones
- pinned Ghostty runtime can be bundled into `tairi.app`

## Prerequisites

For running or packaging Tairi from source:

- macOS 14 or newer
- Xcode with Swift 6 toolchains available on the command line
- [just](https://github.com/casey/just)
- `trash`
- a local `Ghostty.app` to vendor into the repo

Optional:

- `xcodegen` for UI tests
- an Apple Development signing identity for the UI test runner

## Quick Start

From a fresh clone:

```sh
just vendor-ghostty
just dev
```

If `Ghostty.app` is not installed at `/Applications/Ghostty.app`, pass its path explicitly:

```sh
just vendor-ghostty "/path/to/Ghostty.app"
```

Expected result:

- the app launches
- one window opens
- the first terminal tile is backed by the vendored Ghostty runtime

If you are only using a prebuilt app bundle instead of building from source, you
do not need a local `Ghostty.app`.

Custom startup strips can be passed through to the dev app:

```sh
just dev -- --strip 1,1,1 --strip 0.5,1
```

## Packaging

Build a distributable bundle:

```sh
just app
```

Build and install into your user Applications folder:

```sh
just install
```

`just install` updates the existing installed copy if one already exists.

The bundled runtime is placed at:

- `tairi.app/Contents/Frameworks/GhosttyRuntime.app`
- `tairi.app/Contents/Resources/ghostty`

There is no runtime fallback to `/Applications/Ghostty.app`.
Development uses the vendored runtime under `Vendor/Ghostty/...`.

## Contributing

For day-to-day development, the main loop is:

```sh
just dev
```

Run unit tests with:

```sh
swift test
```

UI tests currently require extra local setup:

- `xcodegen` installed
- a working Apple Development signing identity

Run them with:

```sh
./scripts/test-ui.sh
```

Common first-run issues:

- `just vendor-ghostty` fails if `Ghostty.app` is not present at the default path
- `just install` expects `trash` to be installed
- UI tests fail without a local signing identity

## License

Tairi is available under the MIT license. See [LICENSE](LICENSE).

## Third-Party Software

Tairi vendors and redistributes Ghostty as its terminal runtime, including
Sparkle as bundled inside the copied Ghostty app runtime layout.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for details.

## Docs

- [Ghostty setup](docs/ghostty.md)
- [Logs](docs/logs.md)
- [Crash diagnostics](docs/crash-diagnostics.md)
- [UI testing](docs/ui-testing.md)

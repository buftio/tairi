# tairi

Minimal workspace app inspired by Niri's scrolling philosophy:

- vertical dynamic workspaces
- horizontal strip
- new terminals append as columns instead of resizing existing ones

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
[`Vendor/ghostty-runtime.env`](Vendor/ghostty-runtime.env) into the local cache
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

## Docs

- [Ghostty setup](docs/ghostty.md)
- [Logs](docs/logs.md)
- [Crash diagnostics](docs/crash-diagnostics.md)
- [Release packaging and distribution](docs/release.md)
- [UI testing](docs/ui-testing.md)

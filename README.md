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

Optional:

- `xcodegen` for UI tests
- an Apple Development signing identity for the UI test runner
- a local `Ghostty.app` if you want to override the pinned official Ghostty download

## Quick Start

From a fresh clone:

```sh
just vendor-ghostty
just dev
```

`just vendor-ghostty` downloads the pinned Ghostty runtime declared in
[`Vendor/ghostty-runtime.env`](Vendor/ghostty-runtime.env) into the local cache
under `.local/vendor/Ghostty/...`.

If you want to vendor a local `Ghostty.app` instead, pass its path explicitly:

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
just bundle
```

Build and install into your user Applications folder:

```sh
just install
```

`just install` updates the existing installed copy if one already exists.

The bundled runtime is placed at:

- `tairi.app/Contents/Frameworks/GhosttyRuntime.app`
- `tairi.app/Contents/Resources/ghostty`

Development uses the cached runtime under `.local/vendor/Ghostty/...`.

Release metadata lives in [`scripts/release-config.sh`](scripts/release-config.sh).
That file is the source of truth for:

- app version
- bundle identifier
- minimum supported macOS version

Build release artifacts locally:

```sh
just release-artifacts
```

That produces:

- `dist/release/*.app.zip`
- `dist/release/*.dmg`
- `dist/release/*-checksums.txt`
- `dist/release/homebrew/tairi.rb`

If `TAIRI_CODESIGN_IDENTITY` and Apple notary credentials are configured, the
release script signs and notarizes the artifacts. Otherwise it still produces
local release-shaped artifacts, but Gatekeeper distribution will not be ready.

## Distribution

The intended public distribution channels are:

- GitHub Releases with a notarized `.dmg`
- GitHub Releases with a notarized `.app.zip`
- Homebrew via a tap cask that points at the GitHub Release DMG

The repo includes a GitHub Actions release workflow that publishes the release
artifacts on tag pushes and can optionally update a Homebrew tap.

Required release secrets:

- `APPLE_DEVELOPER_ID_CERTIFICATE_P12_BASE64`
- `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `APPLE_NOTARY_API_KEY_P8`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER`
  - only required for Team API keys

Optional Homebrew tap secret:

- `HOMEBREW_TAP_GITHUB_TOKEN`

Optional GitHub Actions variable:

- `HOMEBREW_TAP_REPOSITORY`
  - defaults to `buftio/homebrew-tap`

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

- `just vendor-ghostty` fails if the pinned Ghostty download changes or cannot be fetched
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

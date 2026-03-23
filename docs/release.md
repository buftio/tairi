# Release Packaging and Distribution

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

The bundled runtime is placed at:

- `tairi.app/Contents/Frameworks/GhosttyRuntime.app`
- `tairi.app/Contents/Resources/ghostty`

Development uses the cached runtime under `.local/vendor/Ghostty/...`.

Release metadata lives in [`scripts/release-config.sh`](../scripts/release-config.sh).
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

## Release Modes

The release automation supports two modes:

- preferred: Developer ID signed and notarized artifacts when
  `TAIRI_CODESIGN_IDENTITY` and notary credentials are configured
- fallback: unsigned, non-notarized artifacts when those credentials are not
  configured

The fallback mode is useful for internal testing, CI dry runs, and validating
the Homebrew plumbing. For public distribution, prefer the signed and notarized
path so the downloaded app bundle is ready for normal Gatekeeper launch.

## Distribution

The intended public distribution channels are:

- GitHub Releases with a notarized `.dmg`
- GitHub Releases with a notarized `.app.zip`
- Homebrew via a tap cask that points at the GitHub Release DMG

Install from Homebrew:

```sh
brew tap buftio/tap
brew install --cask tairi
```

The tap repository is expected to contain:

- `Casks/tairi.rb`

The cask file is generated into `dist/release/homebrew/` by
`./scripts/package-release.sh`. The tap repository can keep its own README and
metadata independently so one tap can host multiple apps.

The repo includes a GitHub Actions release workflow that publishes the release
artifacts on `v*` tag pushes when the tagged commit is on `main`, and can
optionally update a Homebrew tap.

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

## Validation

Validate the generated Homebrew tap locally:

```sh
just validate-homebrew
```

That command creates a temporary local tap, runs `brew style --cask`, and then
runs `brew audit --cask --strict` against the generated cask.

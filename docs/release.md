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

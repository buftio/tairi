# Third-Party Notices

Tairi vendors and redistributes third-party software as part of the development
and bundled app runtime.

## Ghostty

- Project: Ghostty
- Upstream: https://github.com/ghostty-org/ghostty
- License: MIT
- Usage in Tairi:
  - the vendored runtime under `Vendor/Ghostty/<version>/...`
  - the bundled helper app at
    `tairi.app/Contents/Frameworks/GhosttyRuntime.app`
  - copied Ghostty resources at `tairi.app/Contents/Resources/ghostty`

Ghostty is embedded as the terminal runtime used by Tairi tiles.

## Sparkle

- Project: Sparkle
- Upstream: https://github.com/sparkle-project/Sparkle
- License: MIT
- Usage in Tairi:
  - vendored inside the Ghostty runtime copied from `Ghostty.app`
  - redistributed under
    `Vendor/Ghostty/<version>/GhosttyRuntime.app/Contents/Frameworks/Sparkle.framework`
    and the corresponding bundled app path

Sparkle is redistributed because it is part of the copied Ghostty app runtime
layout.

## Notes

- The vendored runtime is created by
  [`scripts/vendor-ghostty.sh`](scripts/vendor-ghostty.sh).
- Tairi itself is licensed under the MIT license. See [`LICENSE`](LICENSE).
- Please refer to the upstream projects for the full license text and current
  notices that apply to their respective code and binaries.

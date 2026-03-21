# Third-Party Notices

Tairi vendors and redistributes third-party software as part of the development
and bundled app runtime.

The built app bundle ships these notice files under:

- `tairi.app/Contents/Resources/ThirdPartyNotices/`
- `Tairi-LICENSE.txt`
- `THIRD_PARTY_NOTICES.md`
- `Ghostty-LICENSE.txt`
- `Sparkle-LICENSE.txt`

## Ghostty

- Project: Ghostty
- Upstream: https://github.com/ghostty-org/ghostty
- License: MIT
- Bundled license text: `Vendor/licenses/Ghostty-LICENSE.txt`
- Usage in Tairi:
  - the local runtime cache under `.local/vendor/Ghostty/<version>/...`
  - the bundled helper app at
    `tairi.app/Contents/Frameworks/GhosttyRuntime.app`
  - copied Ghostty resources at `tairi.app/Contents/Resources/ghostty`

Ghostty is embedded as the terminal runtime used by Tairi tiles.

## Sparkle

- Project: Sparkle
- Upstream: https://github.com/sparkle-project/Sparkle
- License: MIT
- Bundled license text: `Vendor/licenses/Sparkle-LICENSE.txt`
- Usage in Tairi:
  - vendored inside the Ghostty runtime copied from `Ghostty.app`
  - redistributed under
    `.local/vendor/Ghostty/<version>/GhosttyRuntime.app/Contents/Frameworks/Sparkle.framework`
    and the corresponding bundled app path

Sparkle is redistributed because it is part of the copied Ghostty app runtime
layout.

## Notes

- The vendored runtime is created by
  [`scripts/vendor-ghostty.sh`](scripts/vendor-ghostty.sh).
- The pinned Ghostty source and checksum live in
  [`Vendor/ghostty-runtime.env`](Vendor/ghostty-runtime.env).
- The exact upstream license texts bundled with Tairi live in
  [`Vendor/licenses`](Vendor/licenses).
- Tairi itself is licensed under the MIT license. See [`LICENSE`](LICENSE).
- Please refer to the upstream projects for the latest project metadata and any
  additional notices that may apply outside the bundled versions.

# tairi

Minimal workspace app prototype inspired by Niri's scrolling philosophy:

- vertical dynamic workspaces
- horizontal fixed-width terminal strip
- new terminals append as columns instead of resizing existing ones
- pinned Ghostty runtime can be bundled into `tairi.app`

## Run

```sh
just vendor-ghostty
just dev
```

For a distributable bundle:

```sh
just app
```

To build and install into Applications:

```sh
just install
```

If `/Applications` is not writable, the install script falls back to `~/Applications`.

The bundled runtime is placed at:

- `tairi.app/Contents/Frameworks/GhosttyRuntime.app`
- `tairi.app/Contents/Resources/ghostty`

There is no runtime fallback to `/Applications/Ghostty.app`.
Development uses the vendored runtime under `Vendor/Ghostty/...`.

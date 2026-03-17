# Electron Prototype

Small standalone prototype for trying Tairi with Electron plus `ghostty-web`.

## What it does

- opens a single Electron window
- starts one local PTY session in the repo root
- renders that session with `ghostty-web`

## Run

```sh
cd electron-proto
pnpm install
pnpm build
pnpm start
```

For iterative work:

```sh
cd electron-proto
pnpm install
pnpm build:electron
pnpm dev
```

## Notes

- This is intentionally isolated from the native Swift app.
- The backend is still just Electron main process for now, not a separate daemon.
- The goal of this prototype is only to prove `ghostty-web` can render a live shell for Tairi.

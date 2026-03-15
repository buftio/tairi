# Tairi

## Dev Hints

- dev app: `just dev`

## Runtime Source

- Development uses vendored Ghostty from `Vendor/Ghostty/...`

## Logs

- Repo-local log file: `.local/logs/tairi.log`
- Crash reports from the previous unexpected launch: `.local/logs/crash-reports/*.md`
- macOS native crash dumps: `~/Library/Logs/DiagnosticReports/tairi-*.ips`
- Full guide: [docs/logs.md](docs/logs.md)

## Crash Diagnosis

- Check the Markdown crash report first, then the matching `.ips`, then `tairi.log`.
- Full guide: [docs/crash-diagnostics.md](docs/crash-diagnostics.md)

## UI Testing

- Keep accessibility identifiers stable and prefer visible-behavior XCUITests.
- Full guide: [docs/ui-testing.md](docs/ui-testing.md)

# cmux

cmux is oss app which as well it's loated in ~/p/oss/cmux
consult with it's source in

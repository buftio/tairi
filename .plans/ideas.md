# tairi ideas

## 1. AppKit core for Ghostty and resizing

- keep `libghostty` as the center of the app and let the workspace area become more AppKit-driven
- use SwiftUI mostly for chrome around it: sidebar, toolbar, settings, command menus
- make the main workspace area a custom AppKit canvas that handles:
  - layout
  - focus
  - resizing
  - zooming out
  - overview mode
- think of each tile as a native surface host instead of a plain SwiftUI view
- for the beginning, it is probably fine to keep everything live and visible at once
- later, overview mode could support both:
  - fully live tiles
  - snapshot-based tiles

Reasoning:

- Ghostty already fits naturally into native macOS view embedding
- if the app wants `niri`-like movement and a zoomed-out workspace overview, AppKit may give more control than a pure SwiftUI strip

## 2. Browser ideas

- browser tiles should use the same tile abstraction as Ghostty
- a tile could be terminal, browser, preview, or something else later
- the simplest browser start is probably `WKWebView`
- if browser requirements become much heavier later, leave room for a Chromium-based option such as CEF

Things to keep in mind:

- profiles, cookies, and storage sound achievable
- full Chrome parity should not be assumed
- extensions, passkeys, and password-manager support need real testing before promising anything

## 3. Possible stream of other apps

- support other apps not as true embeds, but as streamed or captured surfaces
- that could still fit the same workspace model
- those tiles would probably behave more like companions or previews than fully native embedded apps

Possible surface categories:

- native embedded surface
- embedded browser surface
- streamed external-app surface

## rough direction

1. introduce a tile / surface model first
2. replace the current strip with a custom workspace canvas
3. keep Ghostty as the first real surface type
4. add zoom / overview while still rendering everything live
5. explore browser tiles after the canvas model feels right
6. leave streamed external apps as a later experiment

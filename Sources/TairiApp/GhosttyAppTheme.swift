import AppKit
import GhosttyDyn

struct GhosttyAppTheme: Equatable {
    let background: NSColor
    let foreground: NSColor
    let selectionBackground: NSColor
    let accent: NSColor
    let divider: NSColor
    let destructive: NSColor
    let unfocusedSplitFill: NSColor

    static let fallback = GhosttyAppTheme(
        background: NSColor(calibratedRed: 0.92, green: 0.91, blue: 0.88, alpha: 1),
        foreground: NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.08, alpha: 1),
        selectionBackground: NSColor(calibratedRed: 0.57, green: 0.83, blue: 0.66, alpha: 1),
        accent: NSColor(calibratedRed: 0.54, green: 0.86, blue: 0.62, alpha: 1),
        divider: NSColor(calibratedWhite: 0, alpha: 0.14),
        destructive: NSColor.systemRed,
        unfocusedSplitFill: NSColor(calibratedWhite: 1, alpha: 1)
    )

    init(
        background: NSColor,
        foreground: NSColor,
        selectionBackground: NSColor,
        accent: NSColor,
        divider: NSColor,
        destructive: NSColor,
        unfocusedSplitFill: NSColor
    ) {
        self.background = background.srgb
        self.foreground = foreground.srgb
        self.selectionBackground = selectionBackground.srgb
        self.accent = accent.srgb
        self.divider = divider.srgb
        self.destructive = destructive.srgb
        self.unfocusedSplitFill = unfocusedSplitFill.srgb
    }

    init(config: ghostty_config_t) {
        let background = Self.readColor(named: "background", from: config) ?? Self.fallback.background
        let foreground = Self.readColor(named: "foreground", from: config) ?? Self.fallback.foreground
        let selectionBackground = Self.readColor(named: "selection-background", from: config)
        let splitDivider = Self.readColor(named: "split-divider-color", from: config)
        let unfocusedSplitFill = Self.readColor(named: "unfocused-split-fill", from: config)
        // Ghostty palette slots 0...15 are ANSI semantic colors, not arbitrary accents.
        // Tairi treats bright/dim green as the active accent, red as destructive, and
        // blue/cyan as fallback accents when selection/background colors are weak.
        let red = Self.readPaletteColor(index: 9, from: config)
            ?? Self.readPaletteColor(index: 1, from: config)
        let green = Self.readPaletteColor(index: 10, from: config)
            ?? Self.readPaletteColor(index: 2, from: config)
        let blue = Self.readPaletteColor(index: 12, from: config)
            ?? Self.readPaletteColor(index: 4, from: config)
        let cyan = Self.readPaletteColor(index: 14, from: config)
            ?? Self.readPaletteColor(index: 6, from: config)
        let accent = Self.pickAccent(
            background: background,
            foreground: foreground,
            selectionBackground: selectionBackground,
            green: green,
            blue: blue,
            cyan: cyan
        )

        self.init(
            background: background,
            foreground: foreground,
            selectionBackground: selectionBackground
                ?? Self.derivedSelectionBackground(background: background, foreground: foreground),
            accent: accent,
            divider: splitDivider
                ?? foreground.withAlphaComponent(background.isLightTheme ? 0.16 : 0.24),
            destructive: red ?? Self.fallback.destructive,
            unfocusedSplitFill: unfocusedSplitFill ?? background
        )
    }

    var isLightTheme: Bool { background.isLightTheme }

    var windowBackgroundTop: NSColor {
        background.mixed(with: foreground, fraction: isLightTheme ? 0.03 : 0.10)
    }

    var windowBackgroundBottom: NSColor {
        background.mixed(with: foreground, fraction: isLightTheme ? 0.11 : 0.04)
    }

    var primaryText: NSColor {
        foreground.withAlphaComponent(0.88)
    }

    var secondaryText: NSColor {
        foreground.withAlphaComponent(isLightTheme ? 0.54 : 0.62)
    }

    var sidebarStroke: NSColor {
        divider.withAlphaComponent(isLightTheme ? 0.9 : 1)
    }

    var sidebarShadow: NSColor {
        NSColor.black.withAlphaComponent(isLightTheme ? 0.10 : 0.32)
    }

    var actionBackground: NSColor {
        accent.mixed(with: background, fraction: isLightTheme ? 0.80 : 0.72)
            .withAlphaComponent(isLightTheme ? 0.72 : 0.84)
    }

    var activeWorkspaceFill: NSColor {
        accent.mixed(with: background, fraction: isLightTheme ? 0.18 : 0.26)
    }

    var activeWorkspaceText: NSColor {
        Self.readableTextColor(on: activeWorkspaceFill, preferred: foreground)
    }

    var inactiveWorkspaceFill: NSColor {
        foreground.withAlphaComponent(isLightTheme ? 0.08 : 0.12)
    }

    var sidebarOverlayTop: NSColor {
        background.mixed(with: foreground, fraction: isLightTheme ? 0.02 : 0.16)
            .withAlphaComponent(isLightTheme ? 0.48 : 0.34)
    }

    var sidebarOverlayBottom: NSColor {
        background.mixed(with: accent, fraction: isLightTheme ? 0.04 : 0.10)
            .withAlphaComponent(isLightTheme ? 0.18 : 0.12)
    }

    var sidebarHighlight: NSColor {
        foreground.withAlphaComponent(isLightTheme ? 0.18 : 0.10)
    }

    var paperTextureTint: NSColor {
        background.mixed(with: foreground, fraction: isLightTheme ? 0.34 : 0.18)
    }

    var cardBackground: NSColor {
        background.mixed(with: foreground, fraction: isLightTheme ? 0.05 : 0.12)
            .withAlphaComponent(isLightTheme ? 0.72 : 0.82)
    }

    var cardStroke: NSColor {
        divider.withAlphaComponent(isLightTheme ? 0.85 : 1)
    }

    var navOverlay: NSColor {
        background.mixed(with: foreground, fraction: isLightTheme ? 0.03 : 0.10)
            .withAlphaComponent(isLightTheme ? 0.28 : 0.20)
    }

    var tileBackground: NSColor {
        background.mixed(with: foreground, fraction: isLightTheme ? 0.02 : 0.08)
    }

    var tileHeaderBackground: NSColor {
        unfocusedSplitFill.mixed(with: foreground, fraction: isLightTheme ? 0.06 : 0.18)
            .withAlphaComponent(isLightTheme ? 0.40 : 0.28)
    }

    var tileActiveTitleText: NSColor {
        accent
    }

    var tileActivePathText: NSColor {
        accent.withAlphaComponent(isLightTheme ? 0.78 : 0.86)
    }

    var tileActiveBorder: NSColor {
        accent.withAlphaComponent(0.96)
    }

    var tileInactiveBorder: NSColor {
        foreground.withAlphaComponent(isLightTheme ? 0.14 : 0.22)
    }

    var tileShadow: NSColor {
        accent.withAlphaComponent(isLightTheme ? 0.40 : 0.55)
    }

    var closeButtonFill: NSColor {
        destructive
    }

    var closeButtonBorder: NSColor {
        destructive.mixed(with: .black, fraction: 0.30)
    }

    var resizeGrip: NSColor {
        divider.withAlphaComponent(isLightTheme ? 0.85 : 1)
    }

    private static func readColor(named key: String, from config: ghostty_config_t) -> NSColor? {
        var value = ghostty_config_color_s()
        let didLoad = key.withCString { tairi_ghostty_config_get_color(config, $0, &value) }
        guard didLoad else { return nil }
        return NSColor(ghosttyColor: value)
    }

    private static func readPaletteColor(index: UInt8, from config: ghostty_config_t) -> NSColor? {
        var value = ghostty_config_color_s()
        guard tairi_ghostty_config_get_palette_color(config, index, &value) else {
            return nil
        }
        return NSColor(ghosttyColor: value)
    }

    private static func derivedSelectionBackground(background: NSColor, foreground: NSColor) -> NSColor {
        background.mixed(with: foreground, fraction: background.isLightTheme ? 0.22 : 0.30)
    }

    private static func pickAccent(
        background: NSColor,
        foreground: NSColor,
        selectionBackground: NSColor?,
        green: NSColor?,
        blue: NSColor?,
        cyan: NSColor?
    ) -> NSColor {
        if let green, accentScore(green, against: background) >= 4 {
            return green
        }

        let candidates = [selectionBackground, blue, cyan, foreground].compactMap { $0 }
        return candidates.max { lhs, rhs in
            accentScore(lhs, against: background) < accentScore(rhs, against: background)
        } ?? foreground
    }

    private static func accentScore(_ color: NSColor, against background: NSColor) -> CGFloat {
        (color.contrastRatio(with: background) * 0.9) + (color.saturation * 1.6)
    }

    private static func readableTextColor(on background: NSColor, preferred: NSColor) -> NSColor {
        if preferred.contrastRatio(with: background) >= 4.5 {
            return preferred
        }

        let white = NSColor.white
        let black = NSColor.black
        return white.contrastRatio(with: background) >= black.contrastRatio(with: background) ? white : black
    }
}

private extension NSColor {
    convenience init(ghosttyColor: ghostty_config_color_s) {
        self.init(
            calibratedRed: CGFloat(ghosttyColor.r) / 255,
            green: CGFloat(ghosttyColor.g) / 255,
            blue: CGFloat(ghosttyColor.b) / 255,
            alpha: 1
        )
    }

    var srgb: NSColor {
        usingColorSpace(.sRGB) ?? self
    }

    var isLightTheme: Bool {
        relativeLuminance > 0.5
    }

    var saturation: CGFloat {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        (srgb.usingColorSpace(.deviceRGB) ?? srgb).getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        )
        return saturation
    }

    var relativeLuminance: CGFloat {
        let components = rgbaComponents
        return (0.2126 * components.red.luminanceComponent)
            + (0.7152 * components.green.luminanceComponent)
            + (0.0722 * components.blue.luminanceComponent)
    }

    func contrastRatio(with other: NSColor) -> CGFloat {
        let lhs = relativeLuminance
        let rhs = other.relativeLuminance
        let lighter = max(lhs, rhs)
        let darker = min(lhs, rhs)
        return (lighter + 0.05) / (darker + 0.05)
    }

    func mixed(with other: NSColor, fraction: CGFloat) -> NSColor {
        let clampedFraction = max(0, min(fraction, 1))
        let lhs = rgbaComponents
        let rhs = other.rgbaComponents

        return NSColor(
            calibratedRed: lhs.red + ((rhs.red - lhs.red) * clampedFraction),
            green: lhs.green + ((rhs.green - lhs.green) * clampedFraction),
            blue: lhs.blue + ((rhs.blue - lhs.blue) * clampedFraction),
            alpha: lhs.alpha + ((rhs.alpha - lhs.alpha) * clampedFraction)
        )
    }

    private var rgbaComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let color = srgb
        return (
            red: color.redComponent,
            green: color.greenComponent,
            blue: color.blueComponent,
            alpha: color.alphaComponent
        )
    }
}

private extension CGFloat {
    var luminanceComponent: CGFloat {
        if self <= 0.03928 {
            return self / 12.92
        }
        return pow((self + 0.055) / 1.055, 2.4)
    }
}

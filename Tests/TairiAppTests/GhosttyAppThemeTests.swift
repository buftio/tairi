import AppKit
import XCTest

@testable import TairiApp

final class GhosttyAppThemeTests: XCTestCase {
    func testAppearanceNameUsesAquaForLightThemes() {
        let theme = GhosttyAppTheme(
            background: NSColor.white,
            foreground: NSColor.black,
            selectionBackground: NSColor.systemGreen,
            accent: NSColor.systemGreen,
            divider: NSColor.separatorColor,
            destructive: NSColor.systemRed,
            unfocusedSplitFill: NSColor.white
        )

        XCTAssertTrue(theme.isLightTheme)
        XCTAssertEqual(theme.appearanceName, .aqua)
    }

    func testAppearanceNameUsesDarkAquaForDarkThemes() {
        let theme = GhosttyAppTheme(
            background: NSColor.black,
            foreground: NSColor.white,
            selectionBackground: NSColor.systemGreen,
            accent: NSColor.systemGreen,
            divider: NSColor.separatorColor,
            destructive: NSColor.systemRed,
            unfocusedSplitFill: NSColor.black
        )

        XCTAssertFalse(theme.isLightTheme)
        XCTAssertEqual(theme.appearanceName, .darkAqua)
    }
}

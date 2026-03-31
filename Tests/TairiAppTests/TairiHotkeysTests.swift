import XCTest

@testable import TairiApp

final class TairiHotkeysTests: XCTestCase {
    func testDisplayLabelsUseSharedMacFormatting() {
        XCTAssertEqual(TairiHotkeys.newTile.displayLabel, "⌘N")
        XCTAssertEqual(TairiHotkeys.toggleSidebar.displayLabel, "⌘B")
        XCTAssertEqual(TairiHotkeys.previousWorkspace.displayLabel, "⌥⌘↑")
        XCTAssertEqual(TairiHotkeys.splitHorizontally.displayLabel, "⇧⌘D")
        XCTAssertEqual(TairiHotkeys.toggleFullscreen.displayLabel, "⌃⌘F")
    }

    func testSectionsOrganizeShortcutReferences() {
        let sectionTitles = TairiHotkeys.sections.map(\.title)
        XCTAssertEqual(sectionTitles, ["Search", "Tiles", "Workspaces", "View", "Settings"])

        let entryIDs = TairiHotkeys.sections
            .flatMap(\.entries)
            .map(\.id)
        XCTAssertEqual(Set(entryIDs).count, entryIDs.count)
        XCTAssertTrue(entryIDs.contains("toggleSidebar"))
        XCTAssertTrue(entryIDs.contains("toggleFullscreen"))
        XCTAssertTrue(entryIDs.contains("reloadGhosttyConfiguration"))
    }
}

import XCTest

@testable import TairiApp

final class TairiHotkeysTests: XCTestCase {
    func testDisplayLabelsUseSharedMacFormatting() {
        XCTAssertEqual(TairiHotkeys.newTile.displayLabel, "⌘N")
        XCTAssertEqual(TairiHotkeys.toggleSidebar.displayLabel, "⌘B")
        XCTAssertEqual(TairiHotkeys.previousWorkspace.displayLabel, "⌥⌘↑")
        XCTAssertEqual(TairiHotkeys.splitHorizontally.displayLabel, "⇧⌘D")
    }

    func testSectionsOrganizeShortcutReferences() {
        let sectionTitles = TairiHotkeys.sections.map(\.title)
        XCTAssertEqual(sectionTitles, ["Search", "Tiles", "Workspaces", "View", "Settings"])

        let entryIDs = TairiHotkeys.sections
            .flatMap(\.entries)
            .map(\.id)
        XCTAssertEqual(Set(entryIDs).count, entryIDs.count)
        XCTAssertTrue(entryIDs.contains("toggleSidebar"))
        XCTAssertTrue(entryIDs.contains("reloadGhosttyConfiguration"))
    }

    func testWorkspaceScrollOffsetRequiresWorkspaceModifiersAndVerticalIntent() {
        XCTAssertEqual(
            TairiHotkeys.workspaceScrollOffset(
                modifierFlags: [.command, .option],
                deltaX: 0,
                deltaY: 12
            ),
            -1
        )
        XCTAssertEqual(
            TairiHotkeys.workspaceScrollOffset(
                modifierFlags: [.command, .option],
                deltaX: 1,
                deltaY: -12
            ),
            1
        )
        XCTAssertNil(
            TairiHotkeys.workspaceScrollOffset(
                modifierFlags: [],
                deltaX: 0,
                deltaY: 12
            )
        )
        XCTAssertNil(
            TairiHotkeys.workspaceScrollOffset(
                modifierFlags: [.command, .option],
                deltaX: 12,
                deltaY: 6
            )
        )
    }
}

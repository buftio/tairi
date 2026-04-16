import XCTest

@testable import TairiApp

final class TairiHotkeysTests: XCTestCase {
    func testDisplayLabelsUseSharedMacFormatting() {
        XCTAssertEqual(TairiHotkeys.newTile.displayLabel, "⌘N")
        XCTAssertEqual(TairiHotkeys.newGitTile.displayLabel, "⌘G")
        XCTAssertEqual(TairiHotkeys.toggleSidebar.displayLabel, "⌘B")
        XCTAssertEqual(TairiHotkeys.previousWorkspace.displayLabel, "⌥⌘↑")
        XCTAssertEqual(TairiHotkeys.splitHorizontally.displayLabel, "⇧⌘D")
        XCTAssertEqual(TairiHotkeys.moveTileLeft.displayLabel, "⌥⇧⌘←")
        XCTAssertEqual(TairiHotkeys.moveTileDown.displayLabel, "⌥⇧⌘↓")
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
        XCTAssertTrue(entryIDs.contains("moveTileLeft"))
        XCTAssertTrue(entryIDs.contains("moveTileDown"))
        XCTAssertTrue(entryIDs.contains("newGitTile"))
        XCTAssertFalse(entryIDs.contains("moveTileUp"))
    }

    func testTileReorderDoesNotHandleUpArrow() throws {
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command, .option, .shift],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 126
            )
        )

        XCTAssertNil(TairiHotkeys.tileReorderDirection(for: event))
    }
}

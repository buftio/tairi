import XCTest

@testable import TairiApp

final class TerminalTitleDisplayTests: XCTestCase {
    func testDisplayTitlePreservesOtherTitles() {
        XCTAssertEqual(TerminalTitleDisplay.displayTitle(for: "build"), "build")
        XCTAssertEqual(TerminalTitleDisplay.displayTitle(for: "  deploy  "), "deploy")
        XCTAssertEqual(TerminalTitleDisplay.displayTitle(for: "✳ Claude Code"), "✳ Claude Code")
    }

    func testAbbreviatedPathUsesTilde() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("glite/experiments/shadowing", isDirectory: true)
            .path(percentEncoded: false)

        XCTAssertEqual(TerminalTitleDisplay.abbreviatedPath(homePath), "~/glite/experiments/shadowing")
    }

    func testDisplayPathHidesDuplicateTitle() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("glite/experiments/shadowing", isDirectory: true)
            .path(percentEncoded: false)

        XCTAssertNil(TerminalTitleDisplay.displayPath(forTitle: homePath, path: homePath))
        XCTAssertNil(
            TerminalTitleDisplay.displayPath(
                forTitle: "~/glite/experiments/shadowing",
                path: homePath
            )
        )
    }

    func testDisplayPathKeepsDistinctPath() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("glite/experiments/shadowing", isDirectory: true)
            .path(percentEncoded: false)

        XCTAssertEqual(
            TerminalTitleDisplay.displayPath(
                forTitle: "claude",
                path: homePath
            ),
            "~/glite/experiments/shadowing"
        )
    }
}

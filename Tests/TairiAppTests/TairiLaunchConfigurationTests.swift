import XCTest

@testable import TairiApp

final class TairiLaunchConfigurationTests: XCTestCase {
    func testStripArgumentsAreParsedAndRemovedBeforeGhosttyInit() {
        let configuration = TairiLaunchConfiguration.fromProcessArguments([
            "/tmp/tairi",
            "--strip", "1,1,1",
            "--fullscreen",
            "--strip=0.5,1",
        ])

        XCTAssertNil(configuration.parseError)
        XCTAssertEqual(
            configuration.initialStrips,
            [
                .init(tileWidthFactors: [1, 1, 1]),
                .init(tileWidthFactors: [0.5, 1]),
            ]
        )
        XCTAssertEqual(configuration.ghosttyArguments, ["/tmp/tairi", "--fullscreen"])
    }

    func testInvalidStripValueReturnsParseError() {
        let configuration = TairiLaunchConfiguration.fromProcessArguments([
            "/tmp/tairi",
            "--strip", "1,nope",
        ])

        XCTAssertEqual(
            configuration.parseError,
            "Invalid size \"nope\" in --strip \"1,nope\". Use positive numbers like 1 or 0.5."
        )
        XCTAssertEqual(configuration.resolvedInitialStrips, TairiLaunchConfiguration.defaultStrips)
        XCTAssertEqual(configuration.ghosttyArguments, ["/tmp/tairi"])
    }
}

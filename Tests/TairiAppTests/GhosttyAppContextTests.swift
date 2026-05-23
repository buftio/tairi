import GhosttyDyn
import XCTest

@testable import TairiApp

@MainActor
final class GhosttyAppContextTests: XCTestCase {
    func testReleaseAppFreesAndClearsAppOnce() throws {
        let context = GhosttyAppContext(sessionID: UUID())
        let app = try XCTUnwrap(UnsafeMutableRawPointer(bitPattern: 0x1))
        var freedApps: [ghostty_app_t] = []

        context.app = app
        let releasedApp = context.releaseApp { freedApps.append($0) }
        let releasedAgain = context.releaseApp { freedApps.append($0) }

        XCTAssertEqual(freedApps.count, 1)
        XCTAssertTrue(freedApps.first == app)
        XCTAssertTrue(releasedApp == app)
        XCTAssertNil(releasedAgain)
        XCTAssertNil(context.app)
    }
}

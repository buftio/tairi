import XCTest

@testable import TairiApp

final class GhosttyRuntimeCompatibilityTests: XCTestCase {
    func testVendoredRuntimeVersionIsAuthoritative() {
        let result = GhosttyRuntimeCompatibility.validate(version: "1.3.1", vendoredVersion: "1.3.1")

        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("expected vendored runtime to pass compatibility check, got: \(error.message)")
        }
    }

    func testVendoredRuntimeVersionMismatchFails() {
        let result = GhosttyRuntimeCompatibility.validate(version: "1.3.0", vendoredVersion: "1.3.1")

        switch result {
        case .success:
            XCTFail("expected mismatched vendored runtime to fail compatibility check")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("does not match vendored headers 1.3.1"))
        }
    }

    func testHeaderFallbackAllowsPinnedVersionWithoutVendoredRuntime() {
        let result = GhosttyRuntimeCompatibility.validate(version: "1.3.1", vendoredVersion: nil)

        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("expected supported header version to pass compatibility check, got: \(error.message)")
        }
    }
}

import XCTest
@testable import TairiApp

final class TairiPathsTests: XCTestCase {
    func testGhosttyManifestVersionParsesQuotedValue() {
        let contents = """
        GHOSTTY_VERSION="1.3.1"
        GHOSTTY_URL="https://example.invalid/Ghostty.dmg"
        """

        XCTAssertEqual(TairiPaths.ghosttyManifestVersion(in: contents), "1.3.1")
    }

    func testGhosttyManifestVersionParsesUnquotedValue() {
        let contents = """
        GHOSTTY_VERSION=1.3.1
        """

        XCTAssertEqual(TairiPaths.ghosttyManifestVersion(in: contents), "1.3.1")
    }

    func testRequiredGhosttyVendorVersionDirectoryUsesManifestPinnedVersion() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let vendorDirectory = tempRoot.appendingPathComponent(".local/vendor/Ghostty", isDirectory: true)
        let manifestURL = tempRoot.appendingPathComponent("Vendor/ghostty-runtime.env")
        let manifestDirectory = manifestURL.deletingLastPathComponent()

        try FileManager.default.createDirectory(at: vendorDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)

        try """
        GHOSTTY_VERSION="1.3.1"
        """.write(to: manifestURL, atomically: true, encoding: .utf8)

        let requiredDirectory = vendorDirectory.appendingPathComponent("1.3.1", isDirectory: true)
        let otherDirectory = vendorDirectory.appendingPathComponent("9.9.9", isDirectory: true)

        try FileManager.default.createDirectory(
            at: requiredDirectory.appendingPathComponent("GhosttyRuntime.app", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: otherDirectory.appendingPathComponent("GhosttyRuntime.app", isDirectory: true),
            withIntermediateDirectories: true
        )

        XCTAssertEqual(
            TairiPaths.requiredGhosttyVendorVersionDirectory(
                ghosttyVendorDirectory: vendorDirectory,
                manifestURL: manifestURL
            )?.lastPathComponent,
            "1.3.1"
        )
    }
}

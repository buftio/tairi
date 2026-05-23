import XCTest

@testable import TairiApp

final class GitTileCommandRunnerTests: XCTestCase {
    func testRunDrainsLargeStdoutAndStderr() async throws {
        let result = await GitTileCommandRunner.run(
            "sh",
            arguments: [
                "-c",
                "yes out | head -c 200000; yes err | head -c 200000 >&2",
            ],
            currentDirectoryPath: FileManager.default.temporaryDirectory.path(percentEncoded: false)
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.count, 200000)
        XCTAssertEqual(result.stderr.count, 200000)
    }
}

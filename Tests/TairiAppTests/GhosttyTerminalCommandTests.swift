import XCTest

@testable import TairiApp

final class GhosttyTerminalCommandTests: XCTestCase {
    func testParseShowConfigReadsUnquotedCommand() {
        let output = """
            font-size = 14
            command = /bin/zsh
            shell-integration = detect
            """

        XCTAssertEqual(GhosttyTerminalCommand.parseShowConfig(output), "/bin/zsh")
    }

    func testParseShowConfigDecodesQuotedCommand() {
        let output = #"""
            command = "shell:echo \"hello world\""
            """#

        XCTAssertEqual(GhosttyTerminalCommand.parseShowConfig(output), #"shell:echo "hello world""#)
    }

    func testWrappedCommandShellEscapesAllArguments() {
        let command = GhosttyTerminalCommand.wrappedCommand(
            wrapperInterpreterPath: "/bin/zsh",
            wrapperScriptPath: "/tmp/terminal wrapper.zsh",
            pidFilePath: "/tmp/tairi's session.pid",
            command: "shell:echo 'hello world'"
        )

        XCTAssertEqual(
            command,
            "'/bin/zsh' '/tmp/terminal wrapper.zsh' '/tmp/tairi'\\''s session.pid' 'shell:echo '\\''hello world'\\'''"
        )
    }

    func testConfiguredCommandDrainsLargeStdoutAndStderr() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let script = directory.appendingPathComponent("ghostty", isDirectory: false)
        let contents = """
            #!/bin/sh
            yes err | head -c 200000 >&2
            yes out | head -c 200000
            printf '\\ncommand = /bin/zsh\\n'
            """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path(percentEncoded: false))

        XCTAssertEqual(GhosttyTerminalCommand.configuredCommand(ghosttyBinaryPath: script.path(percentEncoded: false)), "/bin/zsh")
    }
}

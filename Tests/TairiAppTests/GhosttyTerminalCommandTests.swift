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
}

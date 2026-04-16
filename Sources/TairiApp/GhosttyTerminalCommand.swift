import Darwin
import Foundation

struct GhosttyTerminalCommand {
    static func resolvedCommand(ghosttyBinaryPath: String?) -> String {
        if let configuredCommand = configuredCommand(ghosttyBinaryPath: ghosttyBinaryPath) {
            return configuredCommand
        }

        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
            return shell
        }

        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let shellPath = String(cString: shell)
            if !shellPath.isEmpty {
                return shellPath
            }
        }

        return "/bin/zsh"
    }

    static func wrappedCommand(
        wrapperInterpreterPath: String,
        wrapperScriptPath: String,
        pidFilePath: String,
        command: String
    ) -> String {
        let parts = [
            shellEscape(wrapperInterpreterPath),
            shellEscape(wrapperScriptPath),
            shellEscape(pidFilePath),
            shellEscape(command),
        ]
        return parts.joined(separator: " ")
    }

    static func configuredCommand(ghosttyBinaryPath: String?) -> String? {
        guard let ghosttyBinaryPath, !ghosttyBinaryPath.isEmpty else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghosttyBinaryPath, isDirectory: false)
        process.arguments = ["+show-config"]
        process.environment = ProcessInfo.processInfo.environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            TairiLog.write("ghostty command resolve failed launchPath=\(ghosttyBinaryPath) error=\(error.localizedDescription)")
            return nil
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            TairiLog.write("ghostty command resolve failed launchPath=\(ghosttyBinaryPath) status=\(process.terminationStatus)")
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        return parseShowConfig(output)
    }

    static func parseShowConfig(_ output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("command = ") else { continue }

            let rawValue = String(trimmed.dropFirst("command = ".count))
                .trimmingCharacters(in: .whitespaces)
            guard !rawValue.isEmpty else { return nil }

            if let decoded = decodeQuotedValue(rawValue), !decoded.isEmpty {
                return decoded
            }

            return rawValue
        }

        return nil
    }

    private static func decodeQuotedValue(_ rawValue: String) -> String? {
        guard rawValue.count >= 2, rawValue.first == "\"", rawValue.last == "\"" else { return nil }

        var result = ""
        var isEscaping = false

        for character in rawValue.dropFirst().dropLast() {
            if isEscaping {
                switch character {
                case "\"":
                    result.append("\"")
                case "\\":
                    result.append("\\")
                case "n":
                    result.append("\n")
                case "r":
                    result.append("\r")
                case "t":
                    result.append("\t")
                default:
                    result.append(character)
                }
                isEscaping = false
                continue
            }

            if character == "\\" {
                isEscaping = true
                continue
            }

            result.append(character)
        }

        if isEscaping {
            result.append("\\")
        }

        return result
    }

    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

import Foundation

struct GitTileCommandResult: Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum GitTileCommandRunner {
    static func run(
        _ executable: String,
        arguments: [String],
        currentDirectoryPath: String
    ) async -> GitTileCommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env", isDirectory: false)
                process.arguments = [executable] + arguments
                process.currentDirectoryURL = URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)

                var environment = ProcessInfo.processInfo.environment
                let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                if let existingPath = environment["PATH"], !existingPath.isEmpty {
                    environment["PATH"] = "\(existingPath):\(defaultPath)"
                } else {
                    environment["PATH"] = defaultPath
                }
                process.environment = environment

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    continuation.resume(
                        returning: GitTileCommandResult(
                            exitCode: 1,
                            stdout: "",
                            stderr: error.localizedDescription
                        )
                    )
                    return
                }

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(
                    returning: GitTileCommandResult(
                        exitCode: process.terminationStatus,
                        stdout: String(decoding: outputData, as: UTF8.self),
                        stderr: String(decoding: errorData, as: UTF8.self)
                    )
                )
            }
        }
    }
}

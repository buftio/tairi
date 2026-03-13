import Foundation

enum TairiLog {
    private static var repoRoot: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static var url: URL {
        repoRoot
            .appendingPathComponent(".local/logs/tairi.log")
    }

    static func write(_ message: String) {
        let line = "[\(timestamp())] \(message)\n"
        let data = Data(line.utf8)
        let path = url.path(percentEncoded: false)
        let directory = url.deletingLastPathComponent().path(percentEncoded: false)

        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: data)
            return
        }

        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}

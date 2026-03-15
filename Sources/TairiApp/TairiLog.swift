import Foundation

enum TairiLog {
    private static let lock = NSLock()

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static var url: URL {
        TairiPaths.mainLogURL
    }

    static func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }

        let line = "[\(timestamp())] \(message)\n"
        let data = Data(line.utf8)
        let path = url.path(percentEncoded: false)
        TairiPaths.ensureLogDirectories()

        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: data)
            return
        }

        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    static func pointer(_ pointer: UnsafeRawPointer?) -> String {
        guard let pointer else { return "nil" }
        return String(format: "0x%016llx", UInt64(UInt(bitPattern: pointer)))
    }

    static func pointer(_ pointer: UnsafeMutableRawPointer?) -> String {
        pointer.map { self.pointer(UnsafeRawPointer($0)) } ?? "nil"
    }

    static func objectID(_ object: AnyObject) -> String {
        pointer(Unmanaged.passUnretained(object).toOpaque())
    }

    static func recentLines(limit: Int) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        guard
            let data = try? Data(contentsOf: url),
            let contents = String(data: data, encoding: .utf8)
        else {
            return []
        }

        return contents
            .split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(limit)
            .map(String.init)
    }
}

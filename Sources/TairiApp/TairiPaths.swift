import Foundation

enum TairiPaths {
    static let repositoryRoot = resolveRepositoryRoot()

    static let logsDirectory: URL = {
        if let repositoryRoot {
            return repositoryRoot.appendingPathComponent(".local/logs", isDirectory: true)
        }

        let libraryDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        return libraryDirectory.appendingPathComponent("Logs/tairi", isDirectory: true)
    }()

    static let mainLogURL = logsDirectory.appendingPathComponent("tairi.log")
    static let crashReportsDirectory = logsDirectory.appendingPathComponent("crash-reports", isDirectory: true)
    static let sessionMarkerURL = logsDirectory.appendingPathComponent("tairi.session.json")
    static let signalMarkerURL = logsDirectory.appendingPathComponent("tairi.signal")
    static let exceptionMarkerURL = logsDirectory.appendingPathComponent("tairi.exception.txt")
    static let ghosttyConfigURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.mitchellh.ghostty", isDirectory: true)
        .appendingPathComponent("config")
    static let diagnosticReportsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    static let ghosttyVendorDirectory: URL? = repositoryRoot?
        .appendingPathComponent(".local/vendor/Ghostty", isDirectory: true)

    static func ensureLogDirectories() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: crashReportsDirectory, withIntermediateDirectories: true)
    }

    static func latestGhosttyVendorVersionDirectory() -> URL? {
        guard let ghosttyVendorDirectory else { return nil }

        return (try? FileManager.default.contentsOfDirectory(
            at: ghosttyVendorDirectory,
            includingPropertiesForKeys: nil
        ))?
        .filter(\.hasDirectoryPath)
        .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        .last
    }

    private static func resolveRepositoryRoot() -> URL? {
        for candidate in candidateSearchRoots() {
            for ancestor in ancestors(of: candidate) where isRepositoryRoot(ancestor) {
                return ancestor
            }
        }
        return nil
    }

    private static func candidateSearchRoots() -> [URL] {
        var candidates: [URL] = []

        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
        if let pwd = ProcessInfo.processInfo.environment["PWD"] {
            candidates.append(URL(fileURLWithPath: pwd, isDirectory: true))
        }
        if let executableURL = Bundle.main.executableURL {
            candidates.append(executableURL.deletingLastPathComponent())
        }
        candidates.append(Bundle.main.bundleURL)
        candidates.append(Bundle.main.bundleURL.deletingLastPathComponent())

        var seen = Set<String>()
        return candidates.filter { candidate in
            let path = candidate.standardizedFileURL.path(percentEncoded: false)
            return seen.insert(path).inserted
        }
    }

    private static func ancestors(of url: URL) -> [URL] {
        var result: [URL] = []
        var current = url.standardizedFileURL
        var seenPaths = Set<String>()

        while true {
            let currentPath = current.path(percentEncoded: false)
            guard seenPaths.insert(currentPath).inserted else {
                break
            }

            result.append(current)
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path(percentEncoded: false) == currentPath {
                break
            }
            current = parent
        }

        return result
    }

    private static func isRepositoryRoot(_ url: URL) -> Bool {
        let packagePath = url.appendingPathComponent("Package.swift").path(percentEncoded: false)
        let sourcesPath = url.appendingPathComponent("Sources/TairiApp").path(percentEncoded: false)

        return FileManager.default.fileExists(atPath: packagePath)
            && FileManager.default.fileExists(atPath: sourcesPath)
    }
}

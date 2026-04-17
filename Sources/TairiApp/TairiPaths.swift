import Foundation

enum TairiPaths {
    static let repositoryRoot = resolveRepositoryRoot()

    static let logsDirectory: URL = {
        if let repositoryRoot {
            return repositoryRoot.appendingPathComponent(".local/logs", isDirectory: true)
        }

        let libraryDirectory =
            FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        return libraryDirectory.appendingPathComponent("Logs/tairi", isDirectory: true)
    }()

    static let mainLogURL = logsDirectory.appendingPathComponent("tairi.log")
    static let crashReportsDirectory = logsDirectory.appendingPathComponent("crash-reports", isDirectory: true)
    static let terminalSessionDirectory = logsDirectory.appendingPathComponent("terminal-sessions", isDirectory: true)
    static let sessionMarkerURL = logsDirectory.appendingPathComponent("tairi.session.json")
    static let exitMarkerURL = logsDirectory.appendingPathComponent("tairi.exit")
    static let signalMarkerURL = logsDirectory.appendingPathComponent("tairi.signal")
    static let exceptionMarkerURL = logsDirectory.appendingPathComponent("tairi.exception.txt")
    static let ghosttyManifestURL: URL? = repositoryRoot?
        .appendingPathComponent("Vendor/ghostty-runtime.env")
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
        try? fileManager.createDirectory(at: terminalSessionDirectory, withIntermediateDirectories: true)
    }

    static func terminalSessionPIDFileURL(for sessionID: UUID) -> URL {
        try? FileManager.default.createDirectory(at: terminalSessionDirectory, withIntermediateDirectories: true)
        return
            terminalSessionDirectory
            .appendingPathComponent(sessionID.uuidString.lowercased(), isDirectory: false)
            .appendingPathExtension("pid")
    }

    static func requiredGhosttyVendorVersion() -> String? {
        ghosttyManifestVersion(from: ghosttyManifestURL)
    }

    static func requiredGhosttyVendorVersionDirectory() -> URL? {
        requiredGhosttyVendorVersionDirectory(
            ghosttyVendorDirectory: ghosttyVendorDirectory,
            manifestURL: ghosttyManifestURL
        )
    }

    static func requiredGhosttyVendorVersionDirectory(
        ghosttyVendorDirectory: URL?,
        manifestURL: URL?
    ) -> URL? {
        guard let ghosttyVendorDirectory, let version = ghosttyManifestVersion(from: manifestURL) else {
            return nil
        }

        let versionDirectory = ghosttyVendorDirectory.appendingPathComponent(version, isDirectory: true)
        let runtimeDirectory = versionDirectory.appendingPathComponent("GhosttyRuntime.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: runtimeDirectory.path(percentEncoded: false)) else {
            return nil
        }

        return versionDirectory
    }

    static func ghosttyManifestVersion(from manifestURL: URL?) -> String? {
        guard
            let manifestURL,
            let contents = try? String(contentsOf: manifestURL, encoding: .utf8)
        else {
            return nil
        }

        return ghosttyManifestVersion(in: contents)
    }

    static func ghosttyManifestVersion(in contents: String) -> String? {
        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard trimmedLine.hasPrefix("GHOSTTY_VERSION=") else { continue }

            let rawValue = trimmedLine.dropFirst("GHOSTTY_VERSION=".count)
                .trimmingCharacters(in: .whitespaces)

            guard !rawValue.isEmpty else { return nil }

            if rawValue.hasPrefix("\""), rawValue.hasSuffix("\""), rawValue.count >= 2 {
                return String(rawValue.dropFirst().dropLast())
            }

            return String(rawValue)
        }

        return nil
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

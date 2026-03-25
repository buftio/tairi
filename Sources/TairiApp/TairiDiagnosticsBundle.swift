import Foundation

struct TairiDiagnosticsBundleEntry: Equatable {
    let sourceURL: URL
    let relativePath: String
}

enum TairiDiagnosticsBundleError: LocalizedError {
    case archiveFailed(String)

    var errorDescription: String? {
        switch self {
        case .archiveFailed(let details):
            if details.isEmpty {
                return "The diagnostics archive could not be created."
            }
            return "The diagnostics archive could not be created: \(details)"
        }
    }
}

enum TairiDiagnosticsBundle {
    static func defaultArchiveName(now: Date = Date()) -> String {
        "\(bundleFolderName(now: now)).zip"
    }

    static func collectedEntries(
        logsDirectory: URL = TairiPaths.logsDirectory,
        diagnosticReportsDirectory: URL = TairiPaths.diagnosticReportsDirectory,
        mainLogURL: URL = TairiPaths.mainLogURL,
        fileManager: FileManager = .default
    ) -> [TairiDiagnosticsBundleEntry] {
        var entries: [TairiDiagnosticsBundleEntry] = []

        if fileManager.fileExists(atPath: mainLogURL.path(percentEncoded: false)) {
            entries.append(.init(sourceURL: mainLogURL, relativePath: "logs/\(mainLogURL.lastPathComponent)"))
        }

        let crashReportsDirectory = logsDirectory.appendingPathComponent("crash-reports", isDirectory: true)
        entries.append(contentsOf:
            contentsOfDirectory(
                at: crashReportsDirectory,
                includingFilesNamedLike: { $0.hasSuffix(".md") },
                destinationDirectory: "crash-reports",
                fileManager: fileManager
            )
        )

        entries.append(contentsOf:
            contentsOfDirectory(
                at: diagnosticReportsDirectory,
                includingFilesNamedLike: { fileName in
                    fileName.hasPrefix("tairi-") && fileName.hasSuffix(".ips")
                },
                destinationDirectory: "diagnostic-reports",
                fileManager: fileManager
            )
        )

        return entries
    }

    @discardableResult
    static func exportArchive(
        to destinationURL: URL,
        logsDirectory: URL = TairiPaths.logsDirectory,
        diagnosticReportsDirectory: URL = TairiPaths.diagnosticReportsDirectory,
        mainLogURL: URL = TairiPaths.mainLogURL,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> URL {
        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("tairi-diagnostics-\(UUID().uuidString)", isDirectory: true)
        let bundleDirectory = stagingRoot.appendingPathComponent(bundleFolderName(now: now), isDirectory: true)

        try fileManager.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        let entries = collectedEntries(
            logsDirectory: logsDirectory,
            diagnosticReportsDirectory: diagnosticReportsDirectory,
            mainLogURL: mainLogURL,
            fileManager: fileManager
        )

        for entry in entries {
            let destinationFileURL = bundleDirectory.appendingPathComponent(entry.relativePath)
            try fileManager.createDirectory(
                at: destinationFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destinationFileURL.path(percentEncoded: false)) {
                try fileManager.removeItem(at: destinationFileURL)
            }
            try fileManager.copyItem(at: entry.sourceURL, to: destinationFileURL)
        }

        let readmeURL = bundleDirectory.appendingPathComponent("README.txt")
        try renderReadme(
            entries: entries,
            logsDirectory: logsDirectory,
            diagnosticReportsDirectory: diagnosticReportsDirectory,
            mainLogURL: mainLogURL,
            now: now
        ).write(to: readmeURL, atomically: true, encoding: .utf8)

        if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destinationURL)
        }

        try createZipArchive(
            sourceDirectory: bundleDirectory,
            destinationURL: destinationURL
        )

        TairiLog.write(
            "diagnostics bundle exported archive=\(destinationURL.path(percentEncoded: false)) files=\(entries.count)"
        )

        return destinationURL
    }

    private static func contentsOfDirectory(
        at directoryURL: URL,
        includingFilesNamedLike predicate: (String) -> Bool,
        destinationDirectory: String,
        fileManager: FileManager
    ) -> [TairiDiagnosticsBundleEntry] {
        guard
            let urls = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        return urls
            .filter { url in
                guard predicate(url.lastPathComponent) else { return false }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
            .map { url in
                .init(
                    sourceURL: url,
                    relativePath: "\(destinationDirectory)/\(url.lastPathComponent)"
                )
            }
    }

    private static func createZipArchive(sourceDirectory: URL, destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto", isDirectory: false)
        process.arguments = [
            "-c",
            "-k",
            "--sequesterRsrc",
            "--keepParent",
            sourceDirectory.path(percentEncoded: false),
            destinationURL.path(percentEncoded: false),
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let details = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw TairiDiagnosticsBundleError.archiveFailed(details)
        }
    }

    private static func renderReadme(
        entries: [TairiDiagnosticsBundleEntry],
        logsDirectory: URL,
        diagnosticReportsDirectory: URL,
        mainLogURL: URL,
        now: Date
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fileLines: String
        if entries.isEmpty {
            fileLines = """
                No matching diagnostics files were found.

                Checked:
                - \(mainLogURL.path(percentEncoded: false))
                - \(logsDirectory.appendingPathComponent("crash-reports", isDirectory: true).path(percentEncoded: false))
                - \(diagnosticReportsDirectory.path(percentEncoded: false))
                """
        } else {
            fileLines = entries
                .map { "- \($0.relativePath)" }
                .joined(separator: "\n")
        }

        return """
            Tairi diagnostics bundle
            Generated at: \(formatter.string(from: now))

            Included files:
            \(fileLines)
            """
    }

    private static func bundleFolderName(now: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "tairi-diagnostics-\(formatter.string(from: now))"
    }
}

import XCTest

@testable import TairiApp

final class TairiDiagnosticsBundleTests: XCTestCase {
    func testCollectedEntriesIncludeLogCrashReportsAndDiagnosticReports() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let logsDirectory = root.appendingPathComponent("logs", isDirectory: true)
        let crashReportsDirectory = logsDirectory.appendingPathComponent("crash-reports", isDirectory: true)
        let diagnosticReportsDirectory = root.appendingPathComponent("diagnostic-reports", isDirectory: true)
        let mainLogURL = logsDirectory.appendingPathComponent("tairi.log")

        try FileManager.default.createDirectory(at: crashReportsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: diagnosticReportsDirectory, withIntermediateDirectories: true)

        try "log".write(to: mainLogURL, atomically: true, encoding: .utf8)
        try "report-1".write(
            to: crashReportsDirectory.appendingPathComponent("20260325-120000-unexpected-termination.md"),
            atomically: true,
            encoding: .utf8
        )
        try "report-2".write(
            to: crashReportsDirectory.appendingPathComponent("20260324-090000-unexpected-termination.md"),
            atomically: true,
            encoding: .utf8
        )
        try "ips".write(
            to: diagnosticReportsDirectory.appendingPathComponent("tairi-2026-03-25-120000.ips"),
            atomically: true,
            encoding: .utf8
        )
        try "ignore".write(
            to: diagnosticReportsDirectory.appendingPathComponent("other-app-2026-03-25.ips"),
            atomically: true,
            encoding: .utf8
        )

        let entries = TairiDiagnosticsBundle.collectedEntries(
            logsDirectory: logsDirectory,
            diagnosticReportsDirectory: diagnosticReportsDirectory,
            mainLogURL: mainLogURL
        )

        XCTAssertEqual(
            entries.map(\.relativePath),
            [
                "logs/tairi.log",
                "crash-reports/20260325-120000-unexpected-termination.md",
                "crash-reports/20260324-090000-unexpected-termination.md",
                "diagnostic-reports/tairi-2026-03-25-120000.ips",
            ]
        )
    }

    func testExportArchiveFailurePreservesExistingDestination() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let logsDirectory = root.appendingPathComponent("logs", isDirectory: true)
        let diagnosticReportsDirectory = root.appendingPathComponent("diagnostic-reports", isDirectory: true)
        let mainLogURL = logsDirectory.appendingPathComponent("tairi.log")
        let destinationURL = root.appendingPathComponent("diagnostics.zip")

        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: diagnosticReportsDirectory, withIntermediateDirectories: true)
        try "log".write(to: mainLogURL, atomically: true, encoding: .utf8)
        try "original archive".write(to: destinationURL, atomically: true, encoding: .utf8)

        struct ArchiveFailure: Error {}
        var attemptedDestinationURL: URL?

        XCTAssertThrowsError(
            try TairiDiagnosticsBundle.exportArchive(
                to: destinationURL,
                logsDirectory: logsDirectory,
                diagnosticReportsDirectory: diagnosticReportsDirectory,
                mainLogURL: mainLogURL,
                archiveCreator: { _, destinationURL in
                    attemptedDestinationURL = destinationURL
                    throw ArchiveFailure()
                }
            )
        )

        XCTAssertEqual(try String(contentsOf: destinationURL, encoding: .utf8), "original archive")
        XCTAssertNotEqual(attemptedDestinationURL, destinationURL)
        if let attemptedDestinationURL {
            XCTAssertFalse(FileManager.default.fileExists(atPath: attemptedDestinationURL.path(percentEncoded: false)))
        }
    }

    func testCreateZipArchiveDrainsLargeErrorOutputBeforeWaitingForExit() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
        let destinationURL = root.appendingPathComponent("diagnostics.zip")
        let scriptURL = root.appendingPathComponent("noisy-archiver")

        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try """
        #!/bin/sh
        /usr/bin/perl -e 'print STDERR "x" x (512 * 1024)'
        exit 42
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        XCTAssertThrowsError(
            try TairiDiagnosticsBundle.createZipArchive(
                sourceDirectory: sourceDirectory,
                destinationURL: destinationURL,
                executableURL: scriptURL
            )
        ) { error in
            guard case TairiDiagnosticsBundleError.archiveFailed(let details) = error else {
                XCTFail("Expected archiveFailed, got \(error)")
                return
            }
            XCTAssertEqual(details.count, 512 * 1024)
        }
    }
}

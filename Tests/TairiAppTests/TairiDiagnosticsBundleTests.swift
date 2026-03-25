import XCTest

@testable import TairiApp

final class TairiDiagnosticsBundleTests: XCTestCase {
    func testCollectedEntriesIncludeLogCrashReportsAndDiagnosticReports() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
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
}

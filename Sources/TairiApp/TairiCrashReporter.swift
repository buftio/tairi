import AppKit
import Darwin
import Foundation

@MainActor
final class TairiCrashReporter {
    static let shared = TairiCrashReporter()

    private struct SessionState: Codable {
        let launchedAt: String
        let pid: Int32
        let executablePath: String
        let bundleIdentifier: String
        let shortVersion: String
        let bundleVersion: String
        let logsDirectory: String
        let operatingSystemVersion: String
    }

    private static let handledSignals: [Int32] = [
        SIGABRT,
        SIGBUS,
        SIGFPE,
        SIGILL,
        SIGPIPE,
        SIGSEGV,
        SIGTRAP,
    ]

    nonisolated(unsafe) private static var signalMarkerPath: UnsafeMutablePointer<CChar>?
    private var didInstall = false
    private var pendingReportURL: URL?

    private init() {}

    func install() {
        guard !didInstall else { return }
        didInstall = true

        TairiPaths.ensureLogDirectories()
        archiveUnexpectedTerminationIfNeeded()
        writeSessionMarker()
        installExceptionHandler()
        installSignalHandlers()
        TairiLog.write("crash reporter installed logs=\(TairiPaths.logsDirectory.path(percentEncoded: false))")
    }

    func markCleanShutdown() {
        deleteItem(at: TairiPaths.sessionMarkerURL)
        deleteItem(at: TairiPaths.signalMarkerURL)
        deleteItem(at: TairiPaths.exceptionMarkerURL)
        TairiLog.write("application terminated cleanly")
    }

    private func archiveUnexpectedTerminationIfNeeded() {
        guard
            let data = try? Data(contentsOf: TairiPaths.sessionMarkerURL),
            let session = try? JSONDecoder().decode(SessionState.self, from: data)
        else {
            deleteItem(at: TairiPaths.signalMarkerURL)
            deleteItem(at: TairiPaths.exceptionMarkerURL)
            return
        }

        let signalNumber = readSignalNumber()
        let exceptionDetails = try? String(contentsOf: TairiPaths.exceptionMarkerURL, encoding: .utf8)
        let reportContents = renderReport(session: session, signalNumber: signalNumber, exceptionDetails: exceptionDetails)
        let reportURL = TairiPaths.crashReportsDirectory
            .appendingPathComponent("\(reportTimestamp())-unexpected-termination.md")

        do {
            try reportContents.write(to: reportURL, atomically: true, encoding: .utf8)
            pendingReportURL = reportURL
        } catch {
            TairiLog.write("failed to persist crash report: \(error.localizedDescription)")
        }

        deleteItem(at: TairiPaths.sessionMarkerURL)
        deleteItem(at: TairiPaths.signalMarkerURL)
        deleteItem(at: TairiPaths.exceptionMarkerURL)

        if let pendingReportURL {
            TairiLog.write("previous launch ended unexpectedly report=\(pendingReportURL.path(percentEncoded: false))")
        }
    }

    private func writeSessionMarker() {
        let session = SessionState(
            launchedAt: isoTimestamp(Date()),
            pid: getpid(),
            executablePath: Bundle.main.executableURL?.path(percentEncoded: false) ?? CommandLine.arguments.first ?? "unknown",
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
            shortVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            bundleVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            logsDirectory: TairiPaths.logsDirectory.path(percentEncoded: false),
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(session)
            try data.write(to: TairiPaths.sessionMarkerURL, options: .atomic)
        } catch {
            TairiLog.write("failed to write session marker: \(error.localizedDescription)")
        }
    }

    private func installExceptionHandler() {
        NSSetUncaughtExceptionHandler(Self.handleException)
    }

    private func installSignalHandlers() {
        if Self.signalMarkerPath == nil {
            Self.signalMarkerPath = strdup(TairiPaths.signalMarkerURL.path(percentEncoded: false))
        }

        for signal in Self.handledSignals {
            Darwin.signal(signal, Self.handleSignal)
        }
    }

    private func readSignalNumber() -> Int32? {
        guard
            let data = try? Data(contentsOf: TairiPaths.signalMarkerURL),
            data.count == MemoryLayout<Int32>.size
        else {
            return nil
        }

        return data.withUnsafeBytes { $0.load(as: Int32.self) }
    }

    private func renderReport(session: SessionState, signalNumber: Int32?, exceptionDetails: String?) -> String {
        let detectedAt = isoTimestamp(Date())
        let reason = terminationReason(signalNumber: signalNumber, exceptionDetails: exceptionDetails)
        let recentLogLines = TairiLog.recentLines(limit: 400)
        let sessionLogLines =
            recentLogLines
            .filter { line in
                guard
                    let closingBracket = line.firstIndex(of: "]"),
                    line.hasPrefix("[")
                else {
                    return false
                }

                let timestamp = String(line[line.index(after: line.startIndex)..<closingBracket])
                return timestamp >= session.launchedAt
            }
            .suffix(80)
        let logTail = sessionLogLines.isEmpty ? Array(recentLogLines.suffix(80)) : Array(sessionLogLines)
        let logTailSection = logTail.isEmpty ? "_No tairi log lines captured._" : logTail.joined(separator: "\n")
        let diagnosticPath = TairiPaths.diagnosticReportsDirectory.path(percentEncoded: false)

        return """
            # tairi unexpected termination

            detected_at: \(detectedAt)
            launched_at: \(session.launchedAt)
            reason: \(reason)
            pid: \(session.pid)
            executable: \(session.executablePath)
            bundle_identifier: \(session.bundleIdentifier)
            app_version: \(session.shortVersion) (\(session.bundleVersion))
            os_version: \(session.operatingSystemVersion)
            logs_directory: \(session.logsDirectory)
            diagnostic_reports_directory: \(diagnosticPath)

            ## Notes

            Attach this report and the matching `.ips` file from `\(diagnosticPath)` when filing a crash.

            ## Exception Details

            \(exceptionDetails?.isEmpty == false ? exceptionDetails! : "_No uncaught Objective-C exception was recorded before termination._")

            ## Recent Log Tail

            ```text
            \(logTailSection)
            ```
            """
    }

    private func terminationReason(signalNumber: Int32?, exceptionDetails: String?) -> String {
        if let signalNumber {
            return "signal \(signalName(signalNumber)) (\(signalNumber))"
        }
        if exceptionDetails?.isEmpty == false {
            return "uncaught Objective-C exception"
        }
        return "unexpected termination without a clean shutdown marker"
    }

    private func deleteItem(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func isoTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func reportTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func signalName(_ signal: Int32) -> String {
        switch signal {
        case SIGABRT:
            return "SIGABRT"
        case SIGBUS:
            return "SIGBUS"
        case SIGFPE:
            return "SIGFPE"
        case SIGILL:
            return "SIGILL"
        case SIGPIPE:
            return "SIGPIPE"
        case SIGSEGV:
            return "SIGSEGV"
        case SIGTRAP:
            return "SIGTRAP"
        default:
            return "UNKNOWN"
        }
    }

    private static let handleException: @convention(c) (NSException) -> Void = { exception in
        TairiPaths.ensureLogDirectories()

        let report = """
            name: \(exception.name.rawValue)
            reason: \(exception.reason ?? "unknown")

            call_stack:
            \(exception.callStackSymbols.joined(separator: "\n"))
            """

        do {
            try report.write(to: TairiPaths.exceptionMarkerURL, atomically: true, encoding: .utf8)
        } catch {
            TairiLog.write("failed to persist uncaught exception marker: \(error.localizedDescription)")
        }

        TairiLog.write("uncaught exception \(exception.name.rawValue): \(exception.reason ?? "unknown")")
    }

    private static let handleSignal: @convention(c) (Int32) -> Void = { signal in
        guard let signalMarkerPath else {
            Darwin.signal(signal, SIG_DFL)
            Darwin.raise(signal)
            return
        }

        let fd = open(signalMarkerPath, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
        if fd >= 0 {
            var recordedSignal = signal
            withUnsafePointer(to: &recordedSignal) { pointer in
                _ = Darwin.write(fd, pointer, MemoryLayout<Int32>.size)
            }
            _ = Darwin.close(fd)
        }

        Darwin.signal(signal, SIG_DFL)
        Darwin.raise(signal)
    }
}

import AppKit
import Foundation

@MainActor
enum TairiHostDiagnostics {
    static func logLaunchContext() {
        let processInfo = ProcessInfo.processInfo
        let executablePath = Bundle.main.executableURL?.path(percentEncoded: false) ?? "unknown"
        let bundlePath = Bundle.main.bundleURL.path(percentEncoded: false)
        let repositoryPath = TairiPaths.repositoryRoot?.path(percentEncoded: false) ?? "none"
        let isTranslocated = bundlePath.contains("/AppTranslocation/")
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let screenSummary = NSScreen.screens.enumerated()
            .map { index, screen in
                let frame = screen.frame
                return
                    "\(index + 1):\(Int(frame.width))x\(Int(frame.height))@\((String(format: "%.2f", screen.backingScaleFactor)))"
            }
            .joined(separator: ",")

        TairiLog.write(
            "host context os=\"\(processInfo.operatingSystemVersionString)\" locale=\(Locale.current.identifier) timezone=\(TimeZone.current.identifier) lowPower=\(processInfo.isLowPowerModeEnabled) reduceMotion=\(reduceMotion) increaseContrast=\(highContrast)"
        )
        TairiLog.write(
            "host paths executable=\(executablePath) bundle=\(bundlePath) repo=\(repositoryPath) translocated=\(isTranslocated)"
        )
        TairiLog.write(
            "host screens count=\(NSScreen.screens.count) summary=\(screenSummary.isEmpty ? "none" : screenSummary)"
        )
        logBundleSignatureContext(bundlePath: bundlePath)
    }

    private static func logBundleSignatureContext(bundlePath: String) {
        if let quarantine = commandOutput(
            launchPath: "/usr/bin/xattr",
            arguments: ["-p", "com.apple.quarantine", bundlePath]
        )?.trimmingCharacters(in: .whitespacesAndNewlines), !quarantine.isEmpty {
            TairiLog.write("host bundle quarantine=\(quarantine)")
        } else {
            TairiLog.write("host bundle quarantine=none")
        }

        guard
            let codesignOutput = commandOutput(
                launchPath: "/usr/bin/codesign",
                arguments: ["-dvv", bundlePath]
            )
        else {
            TairiLog.write("host bundle codesign=unavailable")
            return
        }

        let interestingLines =
            codesignOutput
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { line in
                line.hasPrefix("Identifier=")
                    || line.hasPrefix("TeamIdentifier=")
                    || line.hasPrefix("Authority=")
                    || line.hasPrefix("Runtime Version=")
            }

        TairiLog.write(
            "host bundle codesign \(interestingLines.isEmpty ? "details=none" : interestingLines.joined(separator: " | "))"
        )
    }

    private static func commandOutput(launchPath: String, arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: launchPath) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            TairiLog.write("host diagnostics command failed path=\(launchPath) error=\(error.localizedDescription)")
            return nil
        }

        process.waitUntilExit()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

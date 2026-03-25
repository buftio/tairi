import AppKit
import Foundation

@MainActor
enum TairiHostDiagnostics {
    static func logStartupPreflight() {
        let bundleURL = Bundle.main.bundleURL
        let resourceURL = Bundle.main.resourceURL
        let executableURL = Bundle.main.executableURL
        let infoPlistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        let ghosttyRuntimeURL = bundleURL.appendingPathComponent("Contents/Frameworks/GhosttyRuntime.app")
        let ghosttyBinaryURL = ghosttyRuntimeURL.appendingPathComponent("Contents/MacOS/ghostty")
        let ghosttyResourcesURL = bundleURL.appendingPathComponent("Contents/Resources/ghostty")
        let appIconURL = bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        let swiftPMResourceBundleURL = bundleURL.appendingPathComponent("tairi_TairiApp.bundle")

        TairiLog.write(
            "startup preflight bundleExists=\(exists(bundleURL)) executableExists=\(exists(executableURL)) infoPlistExists=\(exists(infoPlistURL)) resourcesExists=\(exists(resourceURL))"
        )
        TairiLog.write(
            "startup preflight appIconExists=\(exists(appIconURL)) ghosttyRuntimeExists=\(exists(ghosttyRuntimeURL)) ghosttyBinaryExists=\(exists(ghosttyBinaryURL)) ghosttyResourcesExists=\(exists(ghosttyResourcesURL)) swiftPMBundleExists=\(exists(swiftPMResourceBundleURL))"
        )
        logCodesignVerification(label: "bundle", path: bundleURL.path(percentEncoded: false))
        logCodesignVerification(label: "ghosttyRuntime", path: ghosttyRuntimeURL.path(percentEncoded: false))
    }

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

    private static func logCodesignVerification(label: String, path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            TairiLog.write("startup preflight codesign label=\(label) path=\(path) status=missing")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", path]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            TairiLog.write(
                "startup preflight codesign label=\(label) path=\(path) status=launch_failed error=\(error.localizedDescription)"
            )
            return
        }

        process.waitUntilExit()
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output =
            String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let status = process.terminationStatus == 0 ? "ok" : "failed(\(process.terminationStatus))"
        let summary = output.isEmpty ? "none" : output.replacingOccurrences(of: "\n", with: " | ")

        TairiLog.write(
            "startup preflight codesign label=\(label) path=\(path) status=\(status) output=\(summary)"
        )
    }

    private static func exists(_ url: URL?) -> Bool {
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
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

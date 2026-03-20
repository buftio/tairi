import AppKit
import Foundation

enum GhosttyConfigAccess {
    static func openSettingsFile() {
        let fileManager = FileManager.default
        let configURL = TairiPaths.ghosttyConfigURL
        let directoryURL = configURL.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: configURL.path(percentEncoded: false)) {
                try Data().write(to: configURL, options: .atomic)
            }
            NSWorkspace.shared.open(configURL)
        } catch {
            TairiLog.write("open ghostty settings failed error=\(error.localizedDescription)")
        }
    }
}

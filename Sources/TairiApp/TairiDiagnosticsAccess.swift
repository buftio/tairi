import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum TairiDiagnosticsAccess {
    static func exportBundleInteractively() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = TairiDiagnosticsBundle.defaultArchiveName()
        panel.title = "Export Diagnostics Bundle"
        panel.message = "Create a zip with Tairi crash reports, macOS crash dumps, and the current log."

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        do {
            let archiveURL = try TairiDiagnosticsBundle.exportArchive(to: destinationURL)
            NSWorkspace.shared.activateFileViewerSelecting([archiveURL])
        } catch {
            presentExportError(error)
        }
    }

    private static func presentExportError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t Export Diagnostics Bundle"
        alert.informativeText = error.localizedDescription
        alert.runModal()

        TairiLog.write("diagnostics bundle export failed error=\(error.localizedDescription)")
    }
}

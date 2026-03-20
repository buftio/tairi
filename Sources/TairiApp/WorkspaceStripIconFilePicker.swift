import AppKit
import Foundation
import UniformTypeIdentifiers

enum WorkspaceStripIconFilePicker {
    @MainActor
    static func chooseImageFile(
        for workspace: WorkspaceStore.Workspace,
        store: WorkspaceStore
    ) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = workspace.iconFilePath == nil ? "Choose" : "Change"
        panel.message = "Choose an image file for this strip icon."
        panel.directoryURL = initialDirectoryURL(for: workspace, store: store)

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url?.path(percentEncoded: false)
    }

    @MainActor
    private static func initialDirectoryURL(
        for workspace: WorkspaceStore.Workspace,
        store: WorkspaceStore
    ) -> URL? {
        if let folderPath = WorkspaceStore.normalizedAssignedFolderPath(workspace.folderPath) {
            return URL(fileURLWithPath: folderPath, isDirectory: true)
        }

        if let iconFilePath = WorkspaceStore.normalizedWorkspaceIconFilePath(workspace.iconFilePath) {
            return URL(fileURLWithPath: iconFilePath, isDirectory: false).deletingLastPathComponent()
        }

        if let selectedTileID = store.selectedTileID,
            let pwd = store.tile(selectedTileID)?.pwd,
            !pwd.isEmpty
        {
            return URL(fileURLWithPath: pwd, isDirectory: true)
        }

        return URL(
            fileURLWithPath: TerminalWorkingDirectory.defaultDirectoryForEmptyWorkspace(),
            isDirectory: true
        )
    }
}

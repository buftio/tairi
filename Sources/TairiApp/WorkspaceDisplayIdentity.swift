import AppKit
import Foundation

struct WorkspaceEmptyStateBranding {
    let title: String?
    let icon: NSImage?
    let usesWorkspaceIdentity: Bool
}

enum WorkspaceDisplayIdentity {
    static let untitledStripTitle = "Untitled Strip"

    @MainActor
    static func icon(for workspace: WorkspaceStore.Workspace) -> NSImage? {
        icon(forFolderPath: workspace.folderPath)
    }

    @MainActor
    static func icon(forFolderPath folderPath: String?) -> NSImage? {
        guard let folderPath = WorkspaceStore.normalizedAssignedFolderPath(folderPath) else {
            return nil
        }
        return TerminalHeaderIconResolver.resolveIcon(forWorkingDirectory: folderPath)
    }

    @MainActor
    static func emptyStateBranding(
        for workspace: WorkspaceStore.Workspace,
        defaultIcon: NSImage?
    ) -> WorkspaceEmptyStateBranding {
        if workspace.hasAssignedFolder,
           let icon = icon(for: workspace) {
            return WorkspaceEmptyStateBranding(
                title: emptyStateTitle(for: workspace),
                icon: icon,
                usesWorkspaceIdentity: true
            )
        }

        return WorkspaceEmptyStateBranding(
            title: nil,
            icon: defaultIcon,
            usesWorkspaceIdentity: false
        )
    }

    static func emptyStateTitle(for workspace: WorkspaceStore.Workspace) -> String {
        let trimmedTitle = workspace.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return untitledStripTitle
        }

        if workspace.usesAutomaticTitle, !workspace.hasAssignedFolder {
            return untitledStripTitle
        }

        return trimmedTitle
    }
}

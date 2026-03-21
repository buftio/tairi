import AppKit
import Foundation

enum WorkspaceDisplayIcon {
    case symbol(String)
    case image(NSImage)
}

struct WorkspaceEmptyStateBranding {
    let title: String?
    let icon: WorkspaceDisplayIcon?
    let usesWorkspaceIdentity: Bool
}

enum WorkspaceDisplayIdentity {
    static let untitledStripTitle = "Untitled Strip"

    @MainActor
    static func icon(for workspace: WorkspaceStore.Workspace) -> WorkspaceDisplayIcon? {
        icon(
            forFolderPath: workspace.folderPath,
            iconSymbolName: workspace.iconSymbolName,
            iconFilePath: workspace.iconFilePath
        )
    }

    @MainActor
    static func icon(
        forFolderPath folderPath: String?,
        iconSymbolName: String? = nil,
        iconFilePath: String? = nil
    ) -> WorkspaceDisplayIcon? {
        if let iconFilePath = WorkspaceStore.normalizedWorkspaceIconFilePath(iconFilePath),
            let icon = NSImage(contentsOfFile: iconFilePath)
        {
            return .image(icon)
        }

        if let iconSymbolName = WorkspaceStore.normalizedWorkspaceIconSymbolName(iconSymbolName),
            WorkspaceStripIconCatalog.isSymbolAvailable(iconSymbolName)
        {
            return .symbol(iconSymbolName)
        }

        guard let folderPath = WorkspaceStore.normalizedAssignedFolderPath(folderPath) else {
            return nil
        }

        guard let icon = TerminalHeaderIconResolver.resolveIcon(forWorkingDirectory: folderPath) else {
            return nil
        }
        return .image(icon)
    }

    @MainActor
    static func spotlightIcon(
        forTileWorkingDirectory tileWorkingDirectory: String?,
        workspaceFolderPath: String?,
        workspaceIconSymbolName: String? = nil,
        workspaceIconFilePath: String? = nil
    ) -> WorkspaceDisplayIcon? {
        if let tileIcon = TerminalHeaderIconResolver.resolveIcon(forWorkingDirectory: tileWorkingDirectory) {
            return .image(tileIcon)
        }

        return icon(
            forFolderPath: workspaceFolderPath,
            iconSymbolName: workspaceIconSymbolName,
            iconFilePath: workspaceIconFilePath
        )
    }

    @MainActor
    static func emptyStateBranding(
        for workspace: WorkspaceStore.Workspace,
        defaultIcon: NSImage?
    ) -> WorkspaceEmptyStateBranding {
        if workspace.hasAssignedFolder || workspace.hasCustomIcon,
            let icon = icon(for: workspace)
        {
            return WorkspaceEmptyStateBranding(
                title: emptyStateTitle(for: workspace),
                icon: icon,
                usesWorkspaceIdentity: true
            )
        }

        return WorkspaceEmptyStateBranding(
            title: nil,
            icon: defaultIcon.map(WorkspaceDisplayIcon.image),
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

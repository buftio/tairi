import Combine
import Foundation

extension WorkspaceStore {
    func observeSidebarPersistence() {
        persistenceObserver = $workspaces.sink { [weak self] _ in
            self?.persistSidebarState()
        }
    }

    func persistSidebarState() {
        sidebarPersistence.saveStrips(
            workspaces.compactMap { workspace in
                guard workspace.isPersistent else {
                    return nil
                }

                let customTitle =
                    workspace.usesAutomaticTitle
                    ? nil
                    : workspace.title.trimmingCharacters(in: .whitespacesAndNewlines)

                return PersistedWorkspaceStrip(
                    customTitle: customTitle?.isEmpty == false ? customTitle : nil,
                    folderPath: Self.normalizedAssignedFolderPath(workspace.folderPath),
                    iconSymbolName: Self.normalizedWorkspaceIconSymbolName(workspace.iconSymbolName),
                    iconFilePath: Self.normalizedWorkspaceIconFilePath(workspace.iconFilePath)
                )
            }
        )
    }
}

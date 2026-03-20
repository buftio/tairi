import Foundation

extension WorkspaceStore {
    static func makeInitialState(
        initialTerminalWorkingDirectory: String,
        initialStrips: [TairiLaunchConfiguration.Strip],
        initialTerminalSessionID: UUID,
        persistedStrips: [PersistedWorkspaceStrip]
    ) -> (
        workspaces: [Workspace],
        selectedWorkspaceID: UUID,
        selectedTileID: UUID?
    ) {
        if !persistedStrips.isEmpty {
            let initialWorkingDirectory =
                WorkspaceStore.normalizedAssignedFolderPath(persistedStrips[0].folderPath)
                ?? initialTerminalWorkingDirectory
            let firstTile = Tile(
                pwd: initialWorkingDirectory,
                surface: .terminal(sessionID: initialTerminalSessionID)
            )

            let workspaces = persistedStrips.enumerated().map { index, strip in
                Workspace(
                    title: strip.customTitle ?? "",
                    tiles: index == 0 ? [firstTile] : [],
                    folderPath: strip.folderPath,
                    iconSymbolName: strip.iconSymbolName,
                    iconFilePath: strip.iconFilePath,
                    usesAutomaticTitle: strip.customTitle == nil
                )
            }

            let selectedWorkspaceID = workspaces[0].id
            return (
                workspaces: workspaces,
                selectedWorkspaceID: selectedWorkspaceID,
                selectedTileID: firstTile.id
            )
        }

        let strips = initialStrips.isEmpty ? TairiLaunchConfiguration.defaultStrips : initialStrips
        var hasAssignedInitialSession = false
        var firstTileID: UUID?

        let workspaces = strips.enumerated().map { index, strip in
            let workspaceID = UUID()
            let tiles = strip.tileWidthFactors.map { factor -> Tile in
                let sessionID: UUID
                if hasAssignedInitialSession {
                    sessionID = UUID()
                } else {
                    sessionID = initialTerminalSessionID
                    hasAssignedInitialSession = true
                }

                let tile = Tile(
                    pwd: initialTerminalWorkingDirectory,
                    width: WidthPreset.standard.width * CGFloat(factor),
                    surface: .terminal(sessionID: sessionID)
                )
                if firstTileID == nil {
                    firstTileID = tile.id
                }
                return tile
            }

            return Workspace(
                id: workspaceID,
                title: Self.automaticStripTitle(index: index + 1),
                tiles: tiles
            )
        }

        let selectedWorkspaceID = workspaces.first?.id ?? Workspace(title: Self.automaticStripTitle(index: 1)).id
        return (
            workspaces: workspaces.isEmpty ? [Workspace(title: Self.automaticStripTitle(index: 1))] : workspaces,
            selectedWorkspaceID: selectedWorkspaceID,
            selectedTileID: firstTileID
        )
    }
}

import Foundation

extension WorkspaceStore {
    static func makeInitialState(
        initialTerminalWorkingDirectory: String,
        initialStrips: [TairiLaunchConfiguration.Strip],
        initialTerminalSessionID: UUID
    ) -> (
        workspaces: [Workspace],
        selectedWorkspaceID: UUID,
        selectedTileID: UUID?
    ) {
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
                title: String(format: "%02d", index + 1),
                tiles: tiles
            )
        }

        let selectedWorkspaceID = workspaces.first?.id ?? Workspace(title: "01").id
        return (
            workspaces: workspaces.isEmpty ? [Workspace(title: "01")] : workspaces,
            selectedWorkspaceID: selectedWorkspaceID,
            selectedTileID: firstTileID
        )
    }
}

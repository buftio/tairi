import Combine
import Foundation

enum WorkspaceCanvasLayoutMetrics {
    static let visibleStripLeadingInset: CGFloat = 221  // sidebarLeadingInset(11) + sidebarWidth(210)
    static let horizontalPadding: CGFloat = 9
    static let verticalPadding: CGFloat = 9
    static let tileSpacing: CGFloat = 8
    static let minimumTileHeight: CGFloat = 320
    static let resizeHandleWidth: CGFloat = 18
    static let resizeHandleInset: CGFloat = 28
    static let rowSpacing: CGFloat = 16

    static func stripLeadingInset(sidebarHidden: Bool) -> CGFloat {
        sidebarHidden ? 0 : visibleStripLeadingInset
    }
}

@MainActor
final class WorkspaceStore: ObservableObject {
    enum WidthPreset: String, CaseIterable, Codable {
        case narrow
        case standard
        case wide

        var width: CGFloat {
            switch self {
            case .narrow: 560
            case .standard: 760
            case .wide: 980
            }
        }

        var label: String {
            switch self {
            case .narrow: "Narrow"
            case .standard: "Standard"
            case .wide: "Wide"
            }
        }

        static func closest(to width: CGFloat) -> Self {
            allCases.min(by: { abs($0.width - width) < abs($1.width - width) }) ?? .standard
        }
    }

    enum SurfaceKind: String, Codable, Equatable {
        case terminal
    }

    struct Surface: Equatable {
        var kind: SurfaceKind
        var terminalSessionID: UUID

        static func terminal(sessionID: UUID) -> Surface {
            Surface(kind: .terminal, terminalSessionID: sessionID)
        }
    }

    struct Tile: Identifiable, Equatable {
        let id: UUID
        var columnID: UUID
        var title: String
        var pwd: String?
        var width: CGFloat
        var heightWeight: CGFloat
        var createdAt: Date
        var lastVisitedAt: Date
        var surface: Surface

        init(
            id: UUID = UUID(),
            columnID: UUID = UUID(),
            title: String = "shell",
            pwd: String? = nil,
            width: CGFloat = WidthPreset.standard.width,
            heightWeight: CGFloat = 1,
            createdAt: Date = .now,
            lastVisitedAt: Date = .now,
            surface: Surface
        ) {
            self.id = id
            self.columnID = columnID
            self.title = title
            self.pwd = pwd
            self.width = width
            self.heightWeight = heightWeight
            self.createdAt = createdAt
            self.lastVisitedAt = lastVisitedAt
            self.surface = surface
        }
    }

    struct Column: Identifiable, Equatable {
        let id: UUID
        var tiles: [Tile]

        var width: CGFloat {
            tiles.first?.width ?? WidthPreset.standard.width
        }
    }

    struct Workspace: Identifiable, Equatable {
        let id: UUID
        var title: String
        var tiles: [Tile]
        var horizontalOffset: CGFloat
        var folderPath: String?
        var usesAutomaticTitle: Bool

        var hasAssignedFolder: Bool {
            WorkspaceStore.normalizedAssignedFolderPath(folderPath) != nil
        }

        var isPersistent: Bool {
            !usesAutomaticTitle || hasAssignedFolder
        }

        init(
            id: UUID = UUID(),
            title: String,
            tiles: [Tile] = [],
            horizontalOffset: CGFloat = 0,
            folderPath: String? = nil,
            usesAutomaticTitle: Bool = true
        ) {
            self.id = id
            self.title = title
            self.tiles = tiles
            self.horizontalOffset = horizontalOffset
            self.folderPath = folderPath
            self.usesAutomaticTitle = usesAutomaticTitle
        }
    }

    static let minimumTileWidth: CGFloat = 420
    static let maximumTileWidth: CGFloat = 1400

    @Published private(set) var workspaces: [Workspace]
    @Published var selectedWorkspaceID: UUID
    @Published var selectedTileID: UUID?

    let sidebarPersistence: WorkspaceSidebarPersistence
    var persistenceObserver: AnyCancellable?

    init(
        initialTerminalWorkingDirectory: String = TerminalWorkingDirectory.defaultInitialLaunchDirectory(),
        initialStrips: [TairiLaunchConfiguration.Strip] = TairiLaunchConfiguration.defaultStrips,
        initialTerminalSessionID: UUID = UUID(),
        sidebarPersistence: WorkspaceSidebarPersistence = WorkspaceSidebarPersistence()
    ) {
        self.sidebarPersistence = sidebarPersistence
        let initialState = Self.makeInitialState(
            initialTerminalWorkingDirectory: initialTerminalWorkingDirectory,
            initialStrips: initialStrips,
            initialTerminalSessionID: initialTerminalSessionID,
            persistedStrips: sidebarPersistence.loadStrips()
        )
        workspaces = initialState.workspaces
        selectedWorkspaceID = initialState.selectedWorkspaceID
        selectedTileID = initialState.selectedTileID
        normalize()
        observeSidebarPersistence()
        persistSidebarState()
    }

    var selectedWorkspace: Workspace {
        workspaces.first(where: { $0.id == selectedWorkspaceID }) ?? workspaces[0]
    }

    var selectedTile: Tile? {
        guard let selectedTileID else { return nil }
        return tile(selectedTileID)
    }

    func columns(in workspaceID: UUID) -> [Column] {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return [] }
        return WorkspaceColumnLayout.columns(in: workspace)
    }

    func tiles(in workspaceID: UUID) -> [Tile] {
        workspaces.first(where: { $0.id == workspaceID })?.tiles ?? []
    }

    @discardableResult
    func addTerminalTile(nextTo tileID: UUID? = nil, workingDirectory: String? = nil, sessionID: UUID) -> Tile {
        let tile = Tile(
            pwd: resolveWorkingDirectoryForNewTile(nextTo: tileID, workingDirectory: workingDirectory),
            surface: .terminal(sessionID: sessionID)
        )
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }) else {
            return tile
        }

        if let tileID,
           let index = workspaces[workspaceIndex].tiles.firstIndex(where: { $0.id == tileID }) {
            workspaces[workspaceIndex].tiles.insert(tile, at: index + 1)
        } else {
            workspaces[workspaceIndex].tiles.append(tile)
        }

        selectedTileID = tile.id
        markTileVisited(tile.id)
        normalize()
        return tile
    }

    @discardableResult
    func splitTerminalTile(_ tileID: UUID, workingDirectory: String? = nil, sessionID: UUID) -> Tile? {
        guard let workspaceIndex = workspaces.firstIndex(where: { workspace in
            workspace.tiles.contains(where: { $0.id == tileID })
        }), let tileIndex = workspaces[workspaceIndex].tiles.firstIndex(where: { $0.id == tileID }) else {
            return nil
        }

        let sourceTile = workspaces[workspaceIndex].tiles[tileIndex]
        let splitWeight = max(sourceTile.heightWeight / 2, 0.0001)

        workspaces[workspaceIndex].tiles[tileIndex].heightWeight = splitWeight

        let tile = Tile(
            columnID: sourceTile.columnID,
            pwd: resolveWorkingDirectoryForNewTile(nextTo: tileID, workingDirectory: workingDirectory),
            width: sourceTile.width,
            heightWeight: splitWeight,
            surface: .terminal(sessionID: sessionID)
        )
        workspaces[workspaceIndex].tiles.insert(tile, at: tileIndex + 1)

        selectedWorkspaceID = workspaces[workspaceIndex].id
        selectedTileID = tile.id
        markTileVisited(tile.id)
        normalize()
        return tile
    }

    private func resolveWorkingDirectoryForNewTile(nextTo tileID: UUID?, workingDirectory: String?) -> String {
        if let workingDirectory, !workingDirectory.isEmpty {
            return workingDirectory
        }

        if let folderPath = assignedFolderPathForNewTile(nextTo: tileID) {
            return folderPath
        }

        if let tileID,
           let pwd = tile(tileID)?.pwd,
           !pwd.isEmpty {
            return pwd
        }

        if let selectedTileID,
           let pwd = tile(selectedTileID)?.pwd,
           !pwd.isEmpty {
            return pwd
        }

        return TerminalWorkingDirectory.defaultDirectoryForEmptyWorkspace()
    }

    private func assignedFolderPathForNewTile(nextTo tileID: UUID?) -> String? {
        if let tileID,
           let workspace = workspaceContaining(tileID),
           let folderPath = usableAssignedFolderPath(workspace.folderPath) {
            return folderPath
        }

        guard let workspace = workspaces.first(where: { $0.id == selectedWorkspaceID }) else {
            return nil
        }

        return usableAssignedFolderPath(workspace.folderPath)
    }

    func preferredWorkingDirectoryForNewTile(nextTo tileID: UUID?, fallback: String) -> String {
        assignedFolderPathForNewTile(nextTo: tileID) ?? fallback
    }

    nonisolated static func normalizedAssignedFolderPath(_ folderPath: String?) -> String? {
        guard let folderPath else { return nil }
        let trimmed = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed, isDirectory: true)
            .standardizedFileURL
            .path(percentEncoded: false)
    }

    private func usableAssignedFolderPath(_ folderPath: String?) -> String? {
        guard let normalizedPath = Self.normalizedAssignedFolderPath(folderPath) else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalizedPath, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return nil
        }

        return normalizedPath
    }

    func selectWorkspace(
        _ workspaceID: UUID,
        preferredVisibleMidX: CGFloat? = nil,
        stripLeadingInset: CGFloat = WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: false)
    ) {
        guard workspaces.contains(where: { $0.id == workspaceID }) else { return }
        let nextTileID = preferredTileID(
            in: workspaceID,
            preferredVisibleMidX: preferredVisibleMidX,
            stripLeadingInset: stripLeadingInset
        )
        guard selectedWorkspaceID != workspaceID || selectedTileID != nextTileID else { return }

        selectedWorkspaceID = workspaceID
        selectedTileID = nextTileID
        if let nextTileID {
            markTileVisited(nextTileID)
        }
        normalize()
    }

    func selectTile(_ tileID: UUID) {
        guard let workspace = workspaceContaining(tileID) else { return }
        guard selectedTileID != tileID || selectedWorkspaceID != workspace.id else { return }

        selectedTileID = tileID
        selectedWorkspaceID = workspace.id
        markTileVisited(tileID)
    }

    func selectAdjacentTile(offset: Int) {
        let tiles = selectedWorkspace.tiles
        guard !tiles.isEmpty else { return }

        let currentIndex = selectedTileID.flatMap { id in
            tiles.firstIndex(where: { $0.id == id })
        } ?? 0

        let nextIndex = min(max(currentIndex + offset, 0), tiles.count - 1)
        selectedTileID = tiles[nextIndex].id
        markTileVisited(tiles[nextIndex].id)
    }

    func selectAdjacentWorkspace(
        offset: Int,
        preferredVisibleMidX: CGFloat? = nil,
        stripLeadingInset: CGFloat = WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: false)
    ) {
        guard let index = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }) else { return }
        let nextIndex = min(max(index + offset, 0), workspaces.count - 1)
        let workspaceID = workspaces[nextIndex].id
        selectedWorkspaceID = workspaceID
        selectedTileID = preferredTileID(
            in: workspaceID,
            preferredVisibleMidX: preferredVisibleMidX,
            stripLeadingInset: stripLeadingInset
        )
        if let selectedTileID {
            markTileVisited(selectedTileID)
        }
        normalize()
    }

    func scrollSelectedWorkspaceHorizontally(
        deltaX: CGFloat,
        viewportWidth: CGFloat,
        stripLeadingInset: CGFloat
    ) {
        setHorizontalOffset(
            selectedWorkspace.horizontalOffset + deltaX,
            for: selectedWorkspaceID,
            viewportWidth: viewportWidth,
            stripLeadingInset: stripLeadingInset
        )
    }

    func setHorizontalOffset(
        _ offset: CGFloat,
        for workspaceID: UUID,
        viewportWidth: CGFloat,
        stripLeadingInset: CGFloat
    ) {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        let maxOffset = max(
            contentWidth(for: workspaces[workspaceIndex], stripLeadingInset: stripLeadingInset) - viewportWidth,
            0
        )
        let clampedOffset = offset.clamped(to: 0...maxOffset)
        guard workspaces[workspaceIndex].horizontalOffset != clampedOffset else { return }
        workspaces[workspaceIndex].horizontalOffset = clampedOffset
    }

    func revealTile(_ tileID: UUID, viewportWidth: CGFloat, stripLeadingInset: CGFloat) {
        guard let workspace = workspaceContaining(tileID) else { return }
        let targetOffset = centeredOffset(
            for: tileID,
            in: workspace,
            viewportWidth: viewportWidth,
            stripLeadingInset: stripLeadingInset
        )
        setHorizontalOffset(
            targetOffset,
            for: workspace.id,
            viewportWidth: viewportWidth,
            stripLeadingInset: stripLeadingInset
        )
    }

    func setWidth(_ preset: WidthPreset, for tileID: UUID) {
        setWidth(preset.width, for: tileID)
    }

    func setWidth(_ width: CGFloat, for tileID: UUID) {
        let clampedWidth = width.clamped(to: Self.minimumTileWidth...Self.maximumTileWidth)
        guard let columnID = tile(tileID)?.columnID else { return }
        mutateTiles(inColumnID: columnID) { tile in
            tile.width = clampedWidth
        }
    }

    func updateTitle(_ title: String, for tileID: UUID) {
        mutateTile(tileID) { $0.title = title.isEmpty ? "shell" : title }
    }

    func updatePWD(_ pwd: String, for tileID: UUID) {
        mutateTile(tileID) { $0.pwd = pwd }
    }

    func renameWorkspace(_ workspaceID: UUID, to proposedTitle: String) {
        let trimmedTitle = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        if trimmedTitle.isEmpty {
            workspaces[workspaceIndex].usesAutomaticTitle = true
        } else {
            workspaces[workspaceIndex].title = trimmedTitle
            workspaces[workspaceIndex].usesAutomaticTitle = false
        }
        normalize()
    }

    func setWorkspaceFolder(_ workspaceID: UUID, to proposedFolderPath: String?) {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        workspaces[workspaceIndex].folderPath = Self.normalizedAssignedFolderPath(proposedFolderPath)
        normalize()
    }

    enum WorkspaceDropPosition {
        case before
        case after
    }

    func moveWorkspace(_ workspaceID: UUID, relativeTo targetWorkspaceID: UUID, position: WorkspaceDropPosition) {
        guard workspaceID != targetWorkspaceID,
              let sourceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }),
              let targetIndex = workspaces.firstIndex(where: { $0.id == targetWorkspaceID })
        else {
            return
        }

        let workspace = workspaces.remove(at: sourceIndex)
        var adjustedTargetIndex = targetIndex
        if sourceIndex < targetIndex {
            adjustedTargetIndex -= 1
        }

        let insertionIndex: Int
        switch position {
        case .before:
            insertionIndex = adjustedTargetIndex
        case .after:
            insertionIndex = adjustedTargetIndex + 1
        }

        workspaces.insert(workspace, at: min(max(insertionIndex, 0), workspaces.count))
        normalize()
    }

    @discardableResult
    func closeTile(
        _ tileID: UUID,
        preferredVisibleMidX: CGFloat? = nil,
        stripLeadingInset: CGFloat = WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: false)
    ) -> UUID? {
        guard let workspaceIndex = workspaces.firstIndex(where: { workspace in
            workspace.tiles.contains(where: { $0.id == tileID })
        }), let tileIndex = workspaces[workspaceIndex].tiles.firstIndex(where: { $0.id == tileID }) else {
            return selectedTileID
        }

        let workspaceID = workspaces[workspaceIndex].id
        let wasSelectedTile = selectedTileID == tileID
        let neighboringTileIDs = neighboringTileIDs(
            aroundTileAt: tileIndex,
            in: workspaces[workspaceIndex]
        )
        let removedTile = workspaces[workspaceIndex].tiles[tileIndex]
        workspaces[workspaceIndex].tiles.remove(at: tileIndex)
        redistributeHeightAfterRemovingTile(
            removedTile,
            aroundTileAt: tileIndex,
            in: &workspaces[workspaceIndex]
        )

        if wasSelectedTile {
            selectedTileID = preferredNeighborTileID(
                neighboringTileIDs,
                in: workspaces[workspaceIndex],
                preferredVisibleMidX: preferredVisibleMidX,
                stripLeadingInset: stripLeadingInset
            ) ?? preferredTileID(
                in: workspaceID,
                preferredVisibleMidX: preferredVisibleMidX,
                stripLeadingInset: stripLeadingInset
            ) ?? workspaces[workspaceIndex].tiles.first?.id
        }
        normalize()
        return selectedTileID
    }

    func tile(_ tileID: UUID) -> Tile? {
        workspaces.flatMap(\.tiles).first(where: { $0.id == tileID })
    }

    func workspaceID(containing tileID: UUID) -> UUID? {
        workspaceContaining(tileID)?.id
    }

    private func mutateTile(_ tileID: UUID, transform: (inout Tile) -> Void) {
        for workspaceIndex in workspaces.indices {
            guard let tileIndex = workspaces[workspaceIndex].tiles.firstIndex(where: { $0.id == tileID }) else {
                continue
            }
            transform(&workspaces[workspaceIndex].tiles[tileIndex])
            return
        }
    }

    private func mutateTiles(inColumnID columnID: UUID, transform: (inout Tile) -> Void) {
        for workspaceIndex in workspaces.indices {
            for tileIndex in workspaces[workspaceIndex].tiles.indices
            where workspaces[workspaceIndex].tiles[tileIndex].columnID == columnID {
                transform(&workspaces[workspaceIndex].tiles[tileIndex])
            }
        }
    }

    private func markTileVisited(_ tileID: UUID, at date: Date = .now) {
        mutateTile(tileID) { $0.lastVisitedAt = date }
    }

    private func workspaceContaining(_ tileID: UUID) -> Workspace? {
        workspaces.first(where: { workspace in
            workspace.tiles.contains(where: { $0.id == tileID })
        })
    }

    private func preferredTileID(
        in workspaceID: UUID,
        preferredVisibleMidX: CGFloat?,
        stripLeadingInset: CGFloat
    ) -> UUID? {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return nil }
        guard let preferredVisibleMidX else {
            return workspace.tiles.first?.id
        }
        return nearestTileID(
            to: preferredVisibleMidX,
            in: workspace,
            stripLeadingInset: stripLeadingInset
        ) ?? workspace.tiles.first?.id
    }

    private func nearestTileID(
        to visibleMidX: CGFloat,
        in workspace: Workspace,
        stripLeadingInset: CGFloat
    ) -> UUID? {
        let columns = WorkspaceColumnLayout.columns(in: workspace)
        guard !columns.isEmpty else { return nil }

        var x = stripLeadingInset + WorkspaceCanvasLayoutMetrics.horizontalPadding
        var bestTileID: UUID?
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for column in columns {
            let tileMidX = x + (column.width / 2)
            let distance = abs(tileMidX - visibleMidX)
            if distance < bestDistance {
                bestDistance = distance
                bestTileID = column.tiles.first?.id
            }
            x += column.width + WorkspaceCanvasLayoutMetrics.tileSpacing
        }

        return bestTileID
    }

    private func neighboringTileIDs(aroundTileAt tileIndex: Int, in workspace: Workspace) -> [UUID] {
        var tileIDs: [UUID] = []

        if tileIndex > 0 {
            tileIDs.append(workspace.tiles[tileIndex - 1].id)
        }

        if tileIndex + 1 < workspace.tiles.count {
            tileIDs.append(workspace.tiles[tileIndex + 1].id)
        }

        return tileIDs
    }

    private func preferredNeighborTileID(
        _ candidateTileIDs: [UUID],
        in workspace: Workspace,
        preferredVisibleMidX: CGFloat?,
        stripLeadingInset: CGFloat
    ) -> UUID? {
        let existingTileIDs = candidateTileIDs.filter { candidateID in
            workspace.tiles.contains(where: { $0.id == candidateID })
        }
        guard !existingTileIDs.isEmpty else { return nil }

        guard let preferredVisibleMidX else {
            return existingTileIDs.last ?? existingTileIDs.first
        }

        var bestTileID: UUID?
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for candidateID in existingTileIDs {
            guard let tileFrame = tileFrame(for: candidateID, in: workspace, stripLeadingInset: stripLeadingInset) else {
                continue
            }

            let distance = abs(tileFrame.midX - preferredVisibleMidX)
            if distance <= bestDistance {
                bestDistance = distance
                bestTileID = candidateID
            }
        }

        return bestTileID ?? existingTileIDs.last ?? existingTileIDs.first
    }

    private func centeredOffset(
        for tileID: UUID,
        in workspace: Workspace,
        viewportWidth: CGFloat,
        stripLeadingInset: CGFloat
    ) -> CGFloat {
        let anchorX = stripLeadingInset + WorkspaceCanvasLayoutMetrics.horizontalPadding

        if workspace.tiles.first?.id == tileID {
            return 0
        }

        guard let tileFrame = tileFrame(for: tileID, in: workspace, stripLeadingInset: stripLeadingInset) else {
            return workspace.horizontalOffset
        }

        let targetOffset = tileFrame.minX - anchorX
        let maxOffset = max(contentWidth(for: workspace, stripLeadingInset: stripLeadingInset) - viewportWidth, 0)
        return targetOffset.clamped(to: 0...maxOffset)
    }

    private func tileFrame(for tileID: UUID, in workspace: Workspace, stripLeadingInset: CGFloat) -> CGRect? {
        WorkspaceColumnLayout.tileFrame(
            for: tileID,
            in: workspace,
            stripLeadingInset: stripLeadingInset,
            availableHeight: WorkspaceCanvasLayoutMetrics.minimumTileHeight
        )
    }

    private func contentWidth(for workspace: Workspace, stripLeadingInset: CGFloat) -> CGFloat {
        WorkspaceColumnLayout.contentWidth(for: workspace, stripLeadingInset: stripLeadingInset)
    }

    private func redistributeHeightAfterRemovingTile(
        _ removedTile: Tile,
        aroundTileAt tileIndex: Int,
        in workspace: inout Workspace
    ) {
        let siblingIndices = workspace.tiles.indices.filter { index in
            workspace.tiles[index].columnID == removedTile.columnID
        }
        guard !siblingIndices.isEmpty else { return }

        let preferredIndex = siblingIndices.last(where: { $0 < tileIndex }) ?? siblingIndices.first
        guard let preferredIndex else { return }
        workspace.tiles[preferredIndex].heightWeight += removedTile.heightWeight
    }

    private func normalize() {
        var next: [Workspace] = []

        for workspace in workspaces {
            let shouldKeep = !workspace.tiles.isEmpty || workspace.id == selectedWorkspaceID || workspace.isPersistent
            if shouldKeep {
                next.append(workspace)
            }
        }

        if next.isEmpty {
            let fallback = Workspace(title: "01")
            next = [fallback]
            selectedWorkspaceID = fallback.id
        }

        let placeholderCount = next.filter { $0.tiles.isEmpty && !$0.isPersistent }.count
        if placeholderCount == 0 {
            next.append(Workspace(title: String(format: "%02d", next.count + 1)))
        } else if placeholderCount > 1 {
            var keptPlaceholder = false
            next.removeAll { workspace in
                guard workspace.tiles.isEmpty, !workspace.isPersistent else { return false }
                if workspace.id == selectedWorkspaceID && !keptPlaceholder {
                    keptPlaceholder = true
                    return false
                }
                if !keptPlaceholder {
                    keptPlaceholder = true
                    return false
                }
                return true
            }
        }

        for index in next.indices {
            let automaticTitle = String(format: "%02d", index + 1)
            if next[index].usesAutomaticTitle {
                next[index].title = automaticTitle
            } else if next[index].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                next[index].title = automaticTitle
                next[index].usesAutomaticTitle = true
            }
        }

        if !next.contains(where: { $0.id == selectedWorkspaceID }) {
            selectedWorkspaceID = next[0].id
        }

        if let selectedTileID, tile(selectedTileID) == nil {
            self.selectedTileID = next.first(where: { $0.id == selectedWorkspaceID })?.tiles.first?.id
        }

        workspaces = next
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

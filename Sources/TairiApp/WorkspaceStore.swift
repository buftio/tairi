import Foundation

enum WorkspaceCanvasLayoutMetrics {
    static let visibleStripLeadingInset: CGFloat = 248
    static let horizontalPadding: CGFloat = 22
    static let verticalPadding: CGFloat = 22
    static let tileSpacing: CGFloat = 22
    static let minimumTileHeight: CGFloat = 320
    static let resizeHandleWidth: CGFloat = 18
    static let resizeHandleInset: CGFloat = 28
    static let rowSpacing: CGFloat = 22

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

        static let terminal = Surface(kind: .terminal)
    }

    struct Tile: Identifiable, Equatable {
        let id: UUID
        var title: String
        var pwd: String?
        var width: CGFloat
        var createdAt: Date
        var surface: Surface

        init(
            id: UUID = UUID(),
            title: String = "shell",
            pwd: String? = nil,
            width: CGFloat = WidthPreset.standard.width,
            createdAt: Date = .now,
            surface: Surface = .terminal
        ) {
            self.id = id
            self.title = title
            self.pwd = pwd
            self.width = width
            self.createdAt = createdAt
            self.surface = surface
        }
    }

    struct Workspace: Identifiable, Equatable {
        let id: UUID
        var title: String
        var tiles: [Tile]
        var horizontalOffset: CGFloat

        init(id: UUID = UUID(), title: String, tiles: [Tile] = [], horizontalOffset: CGFloat = 0) {
            self.id = id
            self.title = title
            self.tiles = tiles
            self.horizontalOffset = horizontalOffset
        }
    }

    static let minimumTileWidth: CGFloat = 420
    static let maximumTileWidth: CGFloat = 1400

    @Published private(set) var workspaces: [Workspace]
    @Published var selectedWorkspaceID: UUID
    @Published var selectedTileID: UUID?

    init(initialTerminalWorkingDirectory: String = TerminalWorkingDirectory.defaultInitialLaunchDirectory()) {
        let first = Workspace(title: "01")
        let second = Workspace(title: "02")
        workspaces = [first, second]
        selectedWorkspaceID = first.id
        let tile = addTerminalTile(workingDirectory: initialTerminalWorkingDirectory)
        selectedTileID = tile.id
    }

    var selectedWorkspace: Workspace {
        workspaces.first(where: { $0.id == selectedWorkspaceID }) ?? workspaces[0]
    }

    var selectedTile: Tile? {
        guard let selectedTileID else { return nil }
        return tile(selectedTileID)
    }

    func tiles(in workspaceID: UUID) -> [Tile] {
        workspaces.first(where: { $0.id == workspaceID })?.tiles ?? []
    }

    @discardableResult
    func addTerminalTile(nextTo tileID: UUID? = nil, workingDirectory: String? = nil) -> Tile {
        let tile = Tile(pwd: resolveWorkingDirectoryForNewTile(nextTo: tileID, workingDirectory: workingDirectory))
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
        normalize()
        return tile
    }

    private func resolveWorkingDirectoryForNewTile(nextTo tileID: UUID?, workingDirectory: String?) -> String {
        if let workingDirectory, !workingDirectory.isEmpty {
            return workingDirectory
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
        normalize()
    }

    func selectTile(_ tileID: UUID) {
        guard let workspace = workspaceContaining(tileID) else { return }
        guard selectedTileID != tileID || selectedWorkspaceID != workspace.id else { return }

        selectedTileID = tileID
        selectedWorkspaceID = workspace.id
    }

    func selectAdjacentTile(offset: Int) {
        let tiles = selectedWorkspace.tiles
        guard !tiles.isEmpty else { return }

        let currentIndex = selectedTileID.flatMap { id in
            tiles.firstIndex(where: { $0.id == id })
        } ?? 0

        let nextIndex = min(max(currentIndex + offset, 0), tiles.count - 1)
        selectedTileID = tiles[nextIndex].id
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
        mutateTile(tileID) { tile in
            tile.width = width.clamped(to: Self.minimumTileWidth...Self.maximumTileWidth)
        }
    }

    func updateTitle(_ title: String, for tileID: UUID) {
        mutateTile(tileID) { $0.title = title.isEmpty ? "shell" : title }
    }

    func updatePWD(_ pwd: String, for tileID: UUID) {
        mutateTile(tileID) { $0.pwd = pwd }
    }

    func closeTile(_ tileID: UUID) {
        guard let workspaceIndex = workspaces.firstIndex(where: { workspace in
            workspace.tiles.contains(where: { $0.id == tileID })
        }) else {
            return
        }

        workspaces[workspaceIndex].tiles.removeAll(where: { $0.id == tileID })
        if selectedTileID == tileID {
            selectedTileID = workspaces[workspaceIndex].tiles.first?.id
        }
        normalize()
    }

    func tile(_ tileID: UUID) -> Tile? {
        workspaces.flatMap(\.tiles).first(where: { $0.id == tileID })
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
        guard !workspace.tiles.isEmpty else { return nil }

        var x = stripLeadingInset + WorkspaceCanvasLayoutMetrics.horizontalPadding
        var bestTileID: UUID?
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for tile in workspace.tiles {
            let tileMidX = x + (tile.width / 2)
            let distance = abs(tileMidX - visibleMidX)
            if distance < bestDistance {
                bestDistance = distance
                bestTileID = tile.id
            }
            x += tile.width + WorkspaceCanvasLayoutMetrics.tileSpacing
        }

        return bestTileID
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
        var x = stripLeadingInset + WorkspaceCanvasLayoutMetrics.horizontalPadding

        for tile in workspace.tiles {
            let frame = CGRect(x: x, y: 0, width: tile.width, height: WorkspaceCanvasLayoutMetrics.minimumTileHeight)
            if tile.id == tileID {
                return frame
            }
            x += tile.width + WorkspaceCanvasLayoutMetrics.tileSpacing
        }

        return nil
    }

    private func contentWidth(for workspace: Workspace, stripLeadingInset: CGFloat) -> CGFloat {
        guard !workspace.tiles.isEmpty else { return 0 }
        let tileWidths = workspace.tiles.reduce(CGFloat.zero) { partialResult, tile in
            partialResult + tile.width
        }
        let spacing = CGFloat(max(workspace.tiles.count - 1, 0)) * WorkspaceCanvasLayoutMetrics.tileSpacing
        return stripLeadingInset
            + (WorkspaceCanvasLayoutMetrics.horizontalPadding * 2)
            + tileWidths
            + spacing
    }

    private func normalize() {
        var next: [Workspace] = []

        for workspace in workspaces {
            let shouldKeep = !workspace.tiles.isEmpty || workspace.id == selectedWorkspaceID
            if shouldKeep {
                next.append(workspace)
            }
        }

        if next.isEmpty {
            let fallback = Workspace(title: "01")
            next = [fallback]
            selectedWorkspaceID = fallback.id
        }

        let placeholderCount = next.filter { $0.tiles.isEmpty }.count
        if placeholderCount == 0 {
            next.append(Workspace(title: String(format: "%02d", next.count + 1)))
        } else if placeholderCount > 1 {
            var keptPlaceholder = false
            next.removeAll { workspace in
                guard workspace.tiles.isEmpty else { return false }
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
            next[index].title = String(format: "%02d", index + 1)
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

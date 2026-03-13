import AppKit
import SwiftUI

struct WorkspaceCanvasView: NSViewRepresentable {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var runtime: GhosttyRuntime

    func makeNSView(context: Context) -> WorkspaceCanvasContainerView {
        WorkspaceCanvasContainerView(store: store, runtime: runtime)
    }

    func updateNSView(_ nsView: WorkspaceCanvasContainerView, context: Context) {
        let allTileIDs = Set(store.workspaces.flatMap(\.tiles).map(\.id))
        nsView.update(
            workspace: store.selectedWorkspace,
            selectedTileID: store.selectedTileID,
            allTileIDs: allTileIDs
        )
    }
}

@MainActor
final class WorkspaceCanvasContainerView: NSView {
    private let scrollView = NSScrollView()
    private let documentView: WorkspaceCanvasDocumentView
    private var lastSelectedTileID: UUID?

    init(store: WorkspaceStore, runtime: GhosttyRuntime) {
        documentView = WorkspaceCanvasDocumentView(store: store, runtime: runtime)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        configureAccessibility(
            identifier: TairiAccessibility.workspaceCanvas,
            label: "Workspace canvas"
        )

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = documentView

        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        documentView.viewportSize = scrollView.contentView.bounds.size
    }

    func update(workspace: WorkspaceStore.Workspace, selectedTileID: UUID?, allTileIDs: Set<UUID>) {
        documentView.update(
            tiles: workspace.tiles,
            selectedTileID: selectedTileID,
            allTileIDs: allTileIDs
        )
        documentView.viewportSize = scrollView.contentView.bounds.size

        if lastSelectedTileID != selectedTileID, let selectedTileID {
            documentView.scrollTileToVisible(selectedTileID, animated: !TairiEnvironment.isUITesting)
        }
        lastSelectedTileID = selectedTileID
    }
}

@MainActor
final class WorkspaceCanvasDocumentView: NSView {
    private enum Metrics {
        static let horizontalPadding: CGFloat = 22
        static let verticalPadding: CGFloat = 22
        static let tileSpacing: CGFloat = 22
        static let minimumTileHeight: CGFloat = 320
        static let resizeHandleWidth: CGFloat = 18
        static let resizeHandleInset: CGFloat = 28
    }

    private let store: WorkspaceStore
    private let runtime: GhosttyRuntime

    private var tiles: [WorkspaceStore.Tile] = []
    private var selectedTileID: UUID?
    private var tileViews: [UUID: WorkspaceTileHostView] = [:]
    private var resizeHandles: [UUID: WorkspaceTileResizeHandleView] = [:]
    private let inactiveTileStorageView = NSView()

    var viewportSize: CGSize = .zero {
        didSet {
            guard oldValue != viewportSize else { return }
            needsLayout = true
        }
    }

    override var isFlipped: Bool { true }

    init(store: WorkspaceStore, runtime: GhosttyRuntime) {
        self.store = store
        self.runtime = runtime
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        inactiveTileStorageView.isHidden = true
        addSubview(inactiveTileStorageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(tiles: [WorkspaceStore.Tile], selectedTileID: UUID?, allTileIDs: Set<UUID>) {
        self.tiles = tiles
        self.selectedTileID = selectedTileID

        let tileIDs = Set(tiles.map(\.id))
        let handleIDs = Set(tiles.dropLast().map(\.id))

        for (tileID, view) in tileViews where !allTileIDs.contains(tileID) {
            view.dispose()
            view.removeFromSuperview()
            tileViews.removeValue(forKey: tileID)
        }

        for (tileID, view) in tileViews where allTileIDs.contains(tileID) && !tileIDs.contains(tileID) {
            if view.superview !== inactiveTileStorageView {
                view.removeFromSuperview()
                inactiveTileStorageView.addSubview(view)
            }
        }

        for (tileID, handle) in resizeHandles where !handleIDs.contains(tileID) {
            handle.removeFromSuperview()
            resizeHandles.removeValue(forKey: tileID)
        }

        for tile in tiles {
            let tileView = tileViews[tile.id] ?? makeTileView(for: tile)
            if tileView.superview !== self {
                tileView.removeFromSuperview()
                addSubview(tileView)
            }
            tileView.update(tile: tile, selected: tile.id == selectedTileID)
        }

        for tile in tiles.dropLast() {
            let handle = resizeHandles[tile.id] ?? makeResizeHandle(for: tile.id)
            handle.tileID = tile.id
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()

        let viewportWidth = max(viewportSize.width, 1)
        let viewportHeight = max(viewportSize.height, 1)
        let tileHeight = max(viewportHeight - (Metrics.verticalPadding * 2), Metrics.minimumTileHeight)

        inactiveTileStorageView.frame = NSRect(x: -10_000, y: 0, width: 1, height: 1)

        var x = Metrics.horizontalPadding

        for (index, tile) in tiles.enumerated() {
            guard let tileView = tileViews[tile.id] else { continue }
            tileView.frame = NSRect(
                x: x,
                y: Metrics.verticalPadding,
                width: tile.width,
                height: tileHeight
            )

            if index < tiles.count - 1, let handle = resizeHandles[tile.id] {
                let handleCenterX = x + tile.width + (Metrics.tileSpacing / 2)
                handle.frame = NSRect(
                    x: handleCenterX - (Metrics.resizeHandleWidth / 2),
                    y: Metrics.verticalPadding + Metrics.resizeHandleInset,
                    width: Metrics.resizeHandleWidth,
                    height: max(tileHeight - (Metrics.resizeHandleInset * 2), 72)
                )
            }

            x += tile.width + Metrics.tileSpacing
        }

        let contentWidth: CGFloat
        if tiles.isEmpty {
            contentWidth = viewportWidth
        } else {
            contentWidth = max(viewportWidth, x - Metrics.tileSpacing + Metrics.horizontalPadding)
        }

        let contentSize = NSSize(width: contentWidth, height: viewportHeight)
        if frame.size != contentSize {
            setFrameSize(contentSize)
        }
    }

    func scrollTileToVisible(_ tileID: UUID, animated: Bool = true) {
        guard let tileView = tileViews[tileID], let clipView = enclosingScrollView?.contentView else { return }
        let maxOriginX = max(bounds.width - clipView.bounds.width, 0)
        let targetOriginX = min(max(tileView.frame.midX - (clipView.bounds.width / 2), 0), maxOriginX)
        let targetOrigin = NSPoint(x: targetOriginX, y: clipView.bounds.origin.y)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                clipView.animator().setBoundsOrigin(targetOrigin)
            } completionHandler: { [weak scrollView = enclosingScrollView] in
                Task { @MainActor in
                    if let scrollView {
                        scrollView.reflectScrolledClipView(clipView)
                    }
                }
            }
        } else {
            clipView.setBoundsOrigin(targetOrigin)
            enclosingScrollView?.reflectScrolledClipView(clipView)
        }
    }

    private func makeTileView(for tile: WorkspaceStore.Tile) -> WorkspaceTileHostView {
        let view = WorkspaceTileHostView(runtime: runtime, tileID: tile.id)
        tileViews[tile.id] = view
        addSubview(view)
        return view
    }

    private func makeResizeHandle(for tileID: UUID) -> WorkspaceTileResizeHandleView {
        let handle = WorkspaceTileResizeHandleView(store: store, tileID: tileID)
        resizeHandles[tileID] = handle
        addSubview(handle)
        return handle
    }
}

@MainActor
final class WorkspaceTileHostView: NSView {
    private enum Metrics {
        static let cornerRadius: CGFloat = 16
        static let headerHeight: CGFloat = 62
        static let headerPadding: CGFloat = 14
    }

    private let runtime: GhosttyRuntime
    private let titleField = NSTextField(labelWithString: "")
    private let pathField = NSTextField(labelWithString: "")
    private let statusDot = NSView()
    private let headerView = NSView()
    private let surfaceContainerView = NSView()

    private let tileID: UUID

    override var isFlipped: Bool { true }

    init(runtime: GhosttyRuntime, tileID: UUID) {
        self.runtime = runtime
        self.tileID = tileID
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = Metrics.cornerRadius
        layer?.masksToBounds = true
        configureAccessibility(
            identifier: TairiAccessibility.tile(tileID),
            label: "Workspace tile",
            value: "unselected"
        )

        headerView.wantsLayer = true
        addSubview(headerView)

        titleField.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.setAccessibilityIdentifier(TairiAccessibility.tileTitle(tileID))
        addSubview(titleField)

        pathField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        pathField.textColor = .secondaryLabelColor
        pathField.lineBreakMode = .byTruncatingMiddle
        pathField.setAccessibilityIdentifier(TairiAccessibility.tilePath(tileID))
        addSubview(pathField)

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        addSubview(statusDot)

        surfaceContainerView.configureAccessibility(
            identifier: TairiAccessibility.tileSurface(tileID),
            label: "Terminal surface"
        )
        addSubview(surfaceContainerView)
        runtime.attachSurface(tileID: tileID, to: surfaceContainerView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        headerView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: Metrics.headerHeight)
        titleField.frame = NSRect(
            x: Metrics.headerPadding,
            y: 12,
            width: max(bounds.width - 80, 60),
            height: 18
        )
        pathField.frame = NSRect(
            x: Metrics.headerPadding,
            y: 31,
            width: max(bounds.width - 80, 60),
            height: 16
        )
        statusDot.frame = NSRect(x: bounds.width - 22, y: 26, width: 8, height: 8)
        surfaceContainerView.frame = NSRect(
            x: 0,
            y: Metrics.headerHeight,
            width: bounds.width,
            height: max(bounds.height - Metrics.headerHeight, 1)
        )
    }

    override func mouseDown(with event: NSEvent) {
        runtime.focus(tileID: tileID)
        super.mouseDown(with: event)
    }

    func update(tile: WorkspaceStore.Tile, selected: Bool) {
        titleField.stringValue = tile.title
        pathField.stringValue = tile.pwd ?? FileManager.default.currentDirectoryPath
        setAccessibilityLabel("Workspace tile \(tile.title)")
        setAccessibilityValue(selected ? "selected" : "unselected")

        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = (selected ? NSColor.labelColor : NSColor.quaternaryLabelColor).cgColor

        headerView.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.08).cgColor
        statusDot.layer?.backgroundColor = (selected ? NSColor.systemGreen : NSColor.quaternaryLabelColor).cgColor
    }

    func dispose() {
        runtime.detachSurface(tileID: tileID)
    }
}

@MainActor
final class WorkspaceTileResizeHandleView: NSView {
    private let store: WorkspaceStore
    private let gripView = NSView()

    var tileID: UUID

    private var dragStartX: CGFloat = 0
    private var startingWidth: CGFloat = 0

    override var isFlipped: Bool { true }

    init(store: WorkspaceStore, tileID: UUID) {
        self.store = store
        self.tileID = tileID
        super.init(frame: .zero)

        wantsLayer = true
        gripView.wantsLayer = true
        gripView.layer?.cornerRadius = 2
        configureAccessibility(
            identifier: TairiAccessibility.tileResizeHandle(tileID),
            label: "Resize tile",
            value: "draggable"
        )
        addSubview(gripView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        gripView.frame = NSRect(
            x: (bounds.width - 4) / 2,
            y: 10,
            width: 4,
            height: max(bounds.height - 20, 24)
        )
        gripView.layer?.backgroundColor = NSColor.separatorColor.cgColor
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        store.selectTile(tileID)
        setAccessibilityIdentifier(TairiAccessibility.tileResizeHandle(tileID))
        dragStartX = event.locationInWindow.x
        startingWidth = store.tile(tileID)?.width ?? WorkspaceStore.WidthPreset.standard.width
    }

    override func mouseDragged(with event: NSEvent) {
        let deltaX = event.locationInWindow.x - dragStartX
        store.setWidth(startingWidth + deltaX, for: tileID)
    }
}

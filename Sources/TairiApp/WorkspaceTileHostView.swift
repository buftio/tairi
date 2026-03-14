import AppKit

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

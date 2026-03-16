import AppKit

@MainActor
final class WorkspaceTileHostView: NSView {
    private enum Metrics {
        static let cornerRadius: CGFloat = 16
        static let compactCornerRadius: CGFloat = 8
        static let compactCornerRadiusThreshold: CGFloat = 260
        static let headerHeight: CGFloat = 62
        static let headerPadding: CGFloat = 14
        static let closeButtonSize: CGFloat = 12
        static let closeButtonTrailingInset: CGFloat = 14
    }

    private let runtime: GhosttyRuntime
    private let contentContainerView = FlippedContainerView()
    private let borderShapeLayer = CAShapeLayer()
    private let titleField = NSTextField(labelWithString: "")
    private let pathField = NSTextField(labelWithString: "")
    private let closeButton = NSButton(title: "", target: nil, action: nil)
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
        layer?.masksToBounds = false
        borderShapeLayer.fillColor = NSColor.clear.cgColor
        borderShapeLayer.lineJoin = .round
        borderShapeLayer.zPosition = 1
        layer?.addSublayer(borderShapeLayer)
        configureAccessibility(
            identifier: TairiAccessibility.tile(tileID),
            label: "Workspace tile",
            value: "unselected"
        )

        contentContainerView.wantsLayer = true
        addSubview(contentContainerView)

        headerView.wantsLayer = true
        contentContainerView.addSubview(headerView)

        titleField.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.setAccessibilityIdentifier(TairiAccessibility.tileTitle(tileID))
        contentContainerView.addSubview(titleField)

        pathField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        pathField.textColor = .secondaryLabelColor
        pathField.lineBreakMode = .byTruncatingMiddle
        pathField.setAccessibilityIdentifier(TairiAccessibility.tilePath(tileID))
        contentContainerView.addSubview(pathField)

        closeButton.title = ""
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = Metrics.closeButtonSize / 2
        closeButton.layer?.backgroundColor = NSColor.systemRed.cgColor
        closeButton.layer?.borderWidth = 1
        closeButton.layer?.borderColor = NSColor.systemRed.blended(withFraction: 0.3, of: .black)?.cgColor
        closeButton.target = self
        closeButton.action = #selector(closeTile)
        closeButton.setButtonType(.momentaryChange)
        closeButton.contentTintColor = .clear
        closeButton.focusRingType = .none
        closeButton.setAccessibilityIdentifier(TairiAccessibility.tileCloseButton(tileID))
        closeButton.setAccessibilityLabel("Close tile")
        contentContainerView.addSubview(closeButton)

        surfaceContainerView.configureAccessibility(
            identifier: TairiAccessibility.tileSurface(tileID),
            label: "Terminal surface"
        )
        contentContainerView.addSubview(surfaceContainerView)
        runtime.attachTile(tileID, to: surfaceContainerView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let cornerRadius = effectiveCornerRadius()
        let borderWidth = borderShapeLayer.lineWidth
        let borderBounds = bounds.insetBy(dx: -(borderWidth / 2), dy: -(borderWidth / 2))
        let borderCornerRadius = cornerRadius + (borderWidth / 2)
        layer?.cornerRadius = cornerRadius
        layer?.shadowPath = CGPath(
            roundedRect: borderBounds,
            cornerWidth: borderCornerRadius,
            cornerHeight: borderCornerRadius,
            transform: nil
        )
        borderShapeLayer.frame = bounds
        borderShapeLayer.path = CGPath(
            roundedRect: borderBounds,
            cornerWidth: borderCornerRadius,
            cornerHeight: borderCornerRadius,
            transform: nil
        )

        contentContainerView.frame = bounds
        contentContainerView.layer?.cornerRadius = cornerRadius
        contentContainerView.layer?.masksToBounds = true

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
            width: max(bounds.width - 96, 60),
            height: 16
        )
        closeButton.frame = NSRect(
            x: bounds.width - Metrics.closeButtonTrailingInset - Metrics.closeButtonSize,
            y: 15,
            width: Metrics.closeButtonSize,
            height: Metrics.closeButtonSize
        )
        surfaceContainerView.frame = NSRect(
            x: 0,
            y: Metrics.headerHeight,
            width: bounds.width,
            height: max(bounds.height - Metrics.headerHeight, 1)
        )
    }

    override func mouseDown(with event: NSEvent) {
        if workspaceCanvasDocumentView()?.handleTileOverviewClick(tileID) == true {
            return
        }
        runtime.focus(tileID: tileID, transition: .animatedReveal)
        super.mouseDown(with: event)
    }

    func update(tile: WorkspaceStore.Tile, selected: Bool) {
        titleField.stringValue = tile.title
        pathField.stringValue = tile.pwd ?? TerminalWorkingDirectory.defaultDirectoryForEmptyWorkspace()
        setAccessibilityLabel("Workspace tile \(tile.title)")
        setAccessibilityValue(selected ? "selected" : "unselected")

        contentContainerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.backgroundColor = NSColor.clear.cgColor
        borderShapeLayer.lineWidth = selected
            ? WorkspaceTileChromeMetrics.activeBorderWidth
            : WorkspaceTileChromeMetrics.inactiveBorderWidth
        borderShapeLayer.strokeColor = (
            selected
                ? WorkspaceTileChromeMetrics.activeBorderColor
                : WorkspaceTileChromeMetrics.inactiveBorderColor
        ).cgColor
        needsLayout = true
        layer?.shadowColor = WorkspaceTileChromeMetrics.activeBorderColor
            .withAlphaComponent(0.9)
            .cgColor
        layer?.shadowOpacity = selected ? 0.6 : 0
        layer?.shadowRadius = selected ? 18 : 0
        layer?.shadowOffset = .zero

        headerView.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.08).cgColor
        closeButton.layer?.opacity = selected ? 1 : 0.9
    }

    func dispose() {
        runtime.detachTile(tileID, reason: .uiChurn)
    }

    @objc
    private func closeTile() {
        if let canvasDocumentView = workspaceCanvasDocumentView() {
            canvasDocumentView.closeTile(tileID, animated: !TairiEnvironment.isUITesting)
            return
        }
        runtime.closeTile(tileID)
    }

    private func workspaceCanvasDocumentView() -> WorkspaceCanvasDocumentView? {
        var ancestor = superview
        while let view = ancestor {
            if let documentView = view as? WorkspaceCanvasDocumentView {
                return documentView
            }
            ancestor = view.superview
        }
        return nil
    }

    private func effectiveCornerRadius() -> CGFloat {
        let compactDimension = min(bounds.width, bounds.height)
        return compactDimension < Metrics.compactCornerRadiusThreshold
            ? Metrics.compactCornerRadius
            : Metrics.cornerRadius
    }
}

private final class FlippedContainerView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class WorkspaceTileResizeHandleView: NSView {
    private let interactionController: WorkspaceInteractionController
    private let store: WorkspaceStore
    private let gripView = NSView()

    var tileID: UUID

    private var dragStartX: CGFloat = 0
    private var startingWidth: CGFloat = 0

    override var isFlipped: Bool { true }

    init(store: WorkspaceStore, interactionController: WorkspaceInteractionController, tileID: UUID) {
        self.interactionController = interactionController
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
        interactionController.selectTile(tileID)
        setAccessibilityIdentifier(TairiAccessibility.tileResizeHandle(tileID))
        dragStartX = event.locationInWindow.x
        startingWidth = store.tile(tileID)?.width ?? WorkspaceStore.WidthPreset.standard.width
    }

    override func mouseDragged(with event: NSEvent) {
        let deltaX = event.locationInWindow.x - dragStartX
        store.setWidth(startingWidth + deltaX, for: tileID)
    }
}

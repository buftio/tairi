import AppKit
import SwiftUI

@MainActor
final class WorkspaceTileHostView: NSView {
    private enum Metrics {
        static let cornerRadius: CGFloat = 10
        static let compactCornerRadius: CGFloat = 5
        static let compactCornerRadiusThreshold: CGFloat = 260
        static let headerHeight: CGFloat = 34
        static let headerHorizontalInset: CGFloat = 12
        static let closeButtonSize: CGFloat = 12
        static let closeButtonHitSize: CGFloat = 22
        static let closeButtonHitInset: CGFloat = headerHorizontalInset - ((closeButtonHitSize - closeButtonSize) / 2)
        static let iconSize: CGFloat = 16
        static let iconCornerRadius: CGFloat = 3
        static let interItemSpacing: CGFloat = 8
    }

    private let runtime: GhosttyRuntime
    private let contentContainerView = FlippedContainerView()
    private let borderShapeLayer = CAShapeLayer()
    private let borderHighlightLayer = CAShapeLayer()
    private let titleField = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let closeButton = TrafficLightButton(frame: .zero)
    private let headerView = NSView()
    private let headerInteractionView = WorkspaceTileHeaderInteractionView()
    private let surfaceContainerView = NSView()

    private let tileID: UUID
    private let gitTileViewModel = GitTileViewModel()
    private var currentTile: WorkspaceStore.Tile?
    private var currentIsSelected = false
    private var lastHeaderIconPWD: String?
    private weak var coordinatedDocumentView: WorkspaceCanvasDocumentView?
    private var surfaceInteractionCoordinator: GhosttySurfaceInteractionCoordinator?
    private var gitHostingView: NSHostingView<GitTileView>?
    private var isTileReorderLifted = false
    private var isTileReorderDropTarget = false
    private var isTileReorderDragSource = false

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
        borderHighlightLayer.fillColor = NSColor.clear.cgColor
        borderHighlightLayer.lineJoin = .round
        borderHighlightLayer.zPosition = 2
        layer?.addSublayer(borderHighlightLayer)
        configureAccessibility(
            identifier: TairiAccessibility.tile(tileID),
            label: "Workspace tile",
            value: "unselected"
        )

        contentContainerView.wantsLayer = true
        addSubview(contentContainerView)

        headerView.wantsLayer = true
        contentContainerView.addSubview(headerView)

        titleField.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.setAccessibilityIdentifier(TairiAccessibility.tileTitle(tileID))
        headerView.addSubview(titleField)

        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = Metrics.iconCornerRadius
        iconView.layer?.masksToBounds = true
        iconView.imageScaling = .scaleProportionallyUpOrDown
        headerView.addSubview(iconView)

        headerInteractionView.tileID = tileID
        headerInteractionView.onSelect = { [weak self] in
            guard let self else { return }
            self.runtime.focus(tileID: self.tileID, transition: .animatedReveal)
        }
        headerInteractionView.canBeginDrag = { [weak self] in
            self?.workspaceCanvasDocumentView()?.canBeginTileReorderDrag(for: tileID) == true
        }
        headerInteractionView.onBeginDrag = { [weak self] in
            self?.workspaceCanvasDocumentView()?.beginTileReorderDrag(tileID)
        }
        headerInteractionView.onEndDrag = { [weak self] in
            self?.workspaceCanvasDocumentView()?.endTileReorderDrag(tileID)
        }
        headerInteractionView.dragPreviewProvider = { [weak self] in
            self?.tileDragPreview()
        }
        headerView.addSubview(headerInteractionView)

        closeButton.title = ""
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.target = self
        closeButton.action = #selector(closeTile)
        closeButton.setButtonType(.momentaryChange)
        closeButton.focusRingType = .none
        closeButton.setAccessibilityIdentifier(TairiAccessibility.tileCloseButton(tileID))
        closeButton.setAccessibilityLabel("Close tile")
        headerView.addSubview(closeButton)

        surfaceContainerView.configureAccessibility(
            identifier: TairiAccessibility.tileSurface(tileID),
            label: "Tile surface"
        )
        contentContainerView.addSubview(surfaceContainerView)
        gitTileViewModel.onStateChange = { [weak self] _ in
            guard let self, let tile = self.currentTile else { return }
            self.applyHeader(for: tile, selected: self.currentIsSelected, theme: self.runtime.appTheme)
        }
        if let tile = runtime.store.tile(tileID) {
            updateSurfaceContent(for: tile)
        }
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
        let highlightInset: CGFloat = 1.25
        let highlightBounds = bounds.insetBy(dx: highlightInset, dy: highlightInset)
        let highlightCornerRadius = max(cornerRadius - highlightInset, 0)
        borderHighlightLayer.frame = bounds
        borderHighlightLayer.path = CGPath(
            roundedRect: highlightBounds,
            cornerWidth: highlightCornerRadius,
            cornerHeight: highlightCornerRadius,
            transform: nil
        )

        contentContainerView.frame = bounds
        contentContainerView.layer?.cornerRadius = cornerRadius
        contentContainerView.layer?.masksToBounds = true

        headerView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: Metrics.headerHeight)
        headerInteractionView.frame = headerView.bounds
        let closeButtonY = floor((Metrics.headerHeight - Metrics.closeButtonHitSize) / 2)
        titleField.frame = NSRect(
            x: Metrics.headerHorizontalInset + Metrics.closeButtonSize + Metrics.interItemSpacing + Metrics.iconSize
                + Metrics.interItemSpacing,
            y: floor((Metrics.headerHeight - 18) / 2),
            width: max(
                bounds.width
                    - (Metrics.headerHorizontalInset * 2)
                    - Metrics.closeButtonSize
                    - Metrics.iconSize
                    - (Metrics.interItemSpacing * 3),
                60
            ),
            height: 18
        )
        iconView.frame = NSRect(
            x: Metrics.headerHorizontalInset + Metrics.closeButtonSize + Metrics.interItemSpacing,
            y: floor((Metrics.headerHeight - Metrics.iconSize) / 2),
            width: Metrics.iconSize,
            height: Metrics.iconSize
        )
        closeButton.frame = NSRect(
            x: Metrics.closeButtonHitInset,
            y: closeButtonY,
            width: Metrics.closeButtonHitSize,
            height: Metrics.closeButtonHitSize
        )
        surfaceContainerView.frame = NSRect(
            x: 0,
            y: Metrics.headerHeight,
            width: bounds.width,
            height: max(bounds.height - Metrics.headerHeight, 1)
        )
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        syncSurfaceInteractionCoordinator()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncSurfaceInteractionCoordinator()
    }

    override func mouseDown(with event: NSEvent) {
        if workspaceCanvasDocumentView()?.handleTileOverviewClick(tileID) == true {
            return
        }
        runtime.focus(tileID: tileID, transition: .animatedReveal)
        super.mouseDown(with: event)
    }

    func update(tile: WorkspaceStore.Tile, selected: Bool) {
        let theme = runtime.appTheme
        currentTile = tile
        currentIsSelected = selected
        updateSurfaceContent(for: tile)
        syncSurfaceInteractionCoordinator()
        applyHeader(for: tile, selected: selected, theme: theme)
        applyAppearance(animated: false, animationPolicy: .defaultValue)
    }

    func dispose() {
        runtime.session(for: tileID)?.surfaceView.interactionCoordinator = nil
        surfaceInteractionCoordinator = nil
        coordinatedDocumentView = nil
        gitTileViewModel.stopRefreshing()
        runtime.detachTile(tileID, reason: .uiChurn)
    }

    @objc
    private func closeTile() {
        if let canvasDocumentView = workspaceCanvasDocumentView() {
            canvasDocumentView.closeTile(tileID, animated: true)
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

    private func refreshHeaderIcon(for workingDirectory: String?) {
        lastHeaderIconPWD = workingDirectory
        iconView.image = TerminalHeaderIconResolver.resolveIcon(forWorkingDirectory: workingDirectory)
    }

    private func headerTitle(
        for tile: WorkspaceStore.Tile,
        selected: Bool,
        theme: GhosttyAppTheme
    ) -> NSAttributedString {
        let title = displayTitle(for: tile)
        let titleColor =
            selected
            ? theme.primaryText
            : theme.primaryText.withAlphaComponent(0.84)
        let pathColor =
            selected
            ? theme.secondaryText.withAlphaComponent(0.78)
            : theme.secondaryText.withAlphaComponent(0.62)

        let attributedTitle = NSMutableAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: titleColor,
            ]
        )

        if let path = TerminalTitleDisplay.displayPath(forTitle: title, path: tile.pwd) {
            attributedTitle.append(
                NSAttributedString(
                    string: "  \(path)",
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                        .foregroundColor: pathColor,
                    ]
                )
            )
        }

        return attributedTitle
    }

    private func applyHeader(for tile: WorkspaceStore.Tile, selected: Bool, theme: GhosttyAppTheme) {
        let previousHeaderIconPWD = lastHeaderIconPWD
        let title = displayTitle(for: tile)
        titleField.attributedStringValue = headerTitle(for: tile, selected: selected, theme: theme)
        if previousHeaderIconPWD != tile.pwd || iconView.image == nil {
            refreshHeaderIcon(for: tile.pwd)
        }
        let accessibilityPath = TerminalTitleDisplay.displayPath(forTitle: title, path: tile.pwd)
        let accessibilityTitle =
            if let accessibilityPath {
                "\(title) \(accessibilityPath)"
            } else {
                title
            }
        setAccessibilityLabel("Workspace tile \(accessibilityTitle)")
        setAccessibilityValue(selected ? "selected" : "unselected")
    }

    private func displayTitle(for tile: WorkspaceStore.Tile) -> String {
        if tile.surface.kind == .git,
            case .ready(let snapshot) = gitTileViewModel.state
        {
            return snapshot.branchName
        }
        return TerminalTitleDisplay.displayTitle(for: tile.title, path: tile.pwd)
    }

    private func syncSurfaceInteractionCoordinator() {
        guard currentTile?.surface.isTerminal != false else {
            coordinatedDocumentView = nil
            surfaceInteractionCoordinator = nil
            return
        }
        guard let surfaceView = runtime.session(for: tileID)?.surfaceView else { return }
        guard let documentView = workspaceCanvasDocumentView() else {
            surfaceView.interactionCoordinator = nil
            coordinatedDocumentView = nil
            surfaceInteractionCoordinator = nil
            return
        }

        if coordinatedDocumentView !== documentView || surfaceInteractionCoordinator == nil {
            coordinatedDocumentView = documentView
            surfaceInteractionCoordinator = GhosttySurfaceInteractionCoordinator(
                runtime: runtime,
                documentView: documentView,
                snapshotImageProvider: { [weak self] in
                    self?.tairiSnapshotImage()
                }
            )
        }

        surfaceView.interactionCoordinator = surfaceInteractionCoordinator
    }

    private func updateSurfaceContent(for tile: WorkspaceStore.Tile) {
        if tile.surface.isTerminal {
            gitTileViewModel.stopRefreshing()
            gitHostingView?.removeFromSuperview()
            gitHostingView = nil
            runtime.attachTile(tileID, to: surfaceContainerView)
            return
        }

        runtime.detachTile(tileID, reason: .uiChurn)
        gitTileViewModel.updateWorkspaceFolderPath(workspaceFolderPath())
        gitTileViewModel.startRefreshing()

        let rootView = GitTileView(
            model: gitTileViewModel,
            theme: runtime.appTheme,
            selectTile: { [weak self] in
                guard let self else { return }
                self.runtime.focus(tileID: self.tileID, transition: .immediate)
            }
        )

        if let gitHostingView {
            gitHostingView.rootView = rootView
        } else {
            let hostingView = NSHostingView(rootView: rootView)
            hostingView.frame = surfaceContainerView.bounds
            hostingView.autoresizingMask = [.width, .height]
            hostingView.wantsLayer = false
            surfaceContainerView.addSubview(hostingView)
            gitHostingView = hostingView
        }
    }

    func setTileReorderPresentation(
        lifted: Bool,
        dropTarget: Bool,
        dragSource: Bool,
        animated: Bool,
        animationPolicy: AppAnimationPolicy
    ) {
        guard
            lifted != isTileReorderLifted
                || dropTarget != isTileReorderDropTarget
                || dragSource != isTileReorderDragSource
        else {
            return
        }

        isTileReorderLifted = lifted
        isTileReorderDropTarget = dropTarget
        isTileReorderDragSource = dragSource
        applyAppearance(animated: animated, animationPolicy: animationPolicy)
    }

    private func applyAppearance(animated: Bool, animationPolicy: AppAnimationPolicy) {
        let theme = runtime.appTheme
        contentContainerView.layer?.backgroundColor = theme.background.cgColor
        layer?.backgroundColor = NSColor.clear.cgColor
        headerView.layer?.backgroundColor = theme.background.cgColor
        layer?.shadowColor = theme.tileShadow.cgColor
        layer?.shadowOffset = .zero

        let borderWidth =
            currentIsSelected || isTileReorderDropTarget
            ? WorkspaceTileChromeMetrics.activeBorderWidth
            : WorkspaceTileChromeMetrics.inactiveBorderWidth
        let borderColor =
            isTileReorderDropTarget
            ? theme.tileActiveBorder
            : (currentIsSelected ? theme.tileActiveBorder : theme.tileInactiveBorder)
        let highlightWidth: CGFloat =
            isTileReorderDropTarget
            ? 1.2
            : (currentIsSelected ? 0.9 : 0)
        let highlightColor =
            isTileReorderDropTarget
            ? theme.tileActiveBorder
            : (currentIsSelected ? theme.tileActiveBorderHighlight : .clear)
        let shadowOpacity: Float =
            isTileReorderLifted
            ? 0.9
            : (currentIsSelected ? 0.6 : 0)
        let shadowRadius: CGFloat = isTileReorderLifted ? 24 : (currentIsSelected ? 18 : 0)
        let targetAlpha: CGFloat = isTileReorderDragSource ? 0.38 : 1
        let targetZPosition: CGFloat = isTileReorderLifted ? 120 : (isTileReorderDropTarget ? 60 : 0)
        let targetTransform =
            isTileReorderLifted
            ? CATransform3DConcat(
                CATransform3DMakeTranslation(0, -12, 0),
                CATransform3DMakeScale(1.015, 1.015, 1)
            )
            : CATransform3DIdentity
        let duration = animationPolicy.scaledDuration(0.18, requested: animated)

        borderShapeLayer.lineWidth = borderWidth
        borderShapeLayer.strokeColor = borderColor.cgColor
        borderHighlightLayer.lineWidth = highlightWidth
        borderHighlightLayer.strokeColor = highlightColor.cgColor
        closeButton.configureAppearance(
            fillColor: theme.closeButtonFill,
            borderColor: theme.closeButtonBorder,
            opacity: currentIsSelected || isTileReorderLifted ? 1 : 0.92,
            visualDiameter: Metrics.closeButtonSize
        )

        if duration > 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = targetAlpha
            }
            CATransaction.begin()
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            layer?.zPosition = targetZPosition
            layer?.shadowOpacity = shadowOpacity
            layer?.shadowRadius = shadowRadius
            layer?.transform = targetTransform
            CATransaction.commit()
        } else {
            alphaValue = targetAlpha
            layer?.zPosition = targetZPosition
            layer?.shadowOpacity = shadowOpacity
            layer?.shadowRadius = shadowRadius
            layer?.transform = targetTransform
        }

        needsLayout = true
    }

    private func tileDragPreview() -> WorkspaceTileHeaderDragPreview? {
        guard let image = tairiSnapshotImage() else { return nil }
        return WorkspaceTileHeaderDragPreview(
            image: image,
            frame: convert(bounds, to: headerInteractionView)
        )
    }

    private func workspaceFolderPath() -> String? {
        guard let workspaceID = runtime.store.workspaceID(containing: tileID) else { return nil }
        return runtime.store.workspaces.first(where: { $0.id == workspaceID })?.folderPath
    }
}

private final class FlippedContainerView: NSView {
    override var isFlipped: Bool { true }
}

private final class TrafficLightButton: NSButton {
    private let indicatorView = NSView()
    private var visualDiameter: CGFloat = 12

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        indicatorView.wantsLayer = true
        addSubview(indicatorView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func layout() {
        super.layout()
        indicatorView.frame = NSRect(
            x: floor((bounds.width - visualDiameter) / 2),
            y: floor((bounds.height - visualDiameter) / 2),
            width: visualDiameter,
            height: visualDiameter
        )
    }

    func configureAppearance(fillColor: NSColor, borderColor: NSColor, opacity: CGFloat, visualDiameter: CGFloat) {
        self.visualDiameter = visualDiameter
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.opacity = 1
        indicatorView.layer?.backgroundColor = fillColor.cgColor
        indicatorView.layer?.borderColor = borderColor.cgColor
        indicatorView.layer?.borderWidth = 1
        indicatorView.layer?.cornerRadius = visualDiameter / 2
        indicatorView.layer?.opacity = Float(opacity)
        needsLayout = true
    }
}

@MainActor
final class WorkspaceTileResizeHandleView: NSView {
    private let runtime: GhosttyRuntime
    private let interactionController: WorkspaceInteractionController
    private let store: WorkspaceStore
    private let gripView = NSView()

    var tileID: UUID

    private var dragStartX: CGFloat = 0
    private var startingWidth: CGFloat = 0

    override var isFlipped: Bool { true }

    init(
        runtime: GhosttyRuntime,
        store: WorkspaceStore,
        interactionController: WorkspaceInteractionController,
        tileID: UUID
    ) {
        self.runtime = runtime
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
        gripView.layer?.cornerRadius = 2
        gripView.layer?.backgroundColor = NSColor.clear.cgColor
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

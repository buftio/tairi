import AppKit

@MainActor
final class WorkspaceCanvasOverviewRenderer {
    var onTileActivated: ((UUID) -> Void)?

    private var previewViews: [UUID: WorkspaceCanvasOverviewTilePreviewView] = [:]

    func sync(
        tileViews: [UUID: WorkspaceTileHostView],
        allTileIDs: Set<UUID>,
        isOverviewPresented: Bool,
        hostView: NSView
    ) {
        for (tileID, previewView) in previewViews where !allTileIDs.contains(tileID) {
            previewView.restoreLiveTile(into: hostView)
            previewView.removeFromSuperview()
            previewViews.removeValue(forKey: tileID)
        }

        guard isOverviewPresented else {
            teardownOverview(tileViews: tileViews, hostView: hostView)
            return
        }

        for tileID in allTileIDs {
            guard let tileView = tileViews[tileID] else { continue }
            let previewView = previewViews[tileID] ?? makePreviewView(for: tileID)
            previewView.isHidden = false
            previewView.onPrimaryClick = { [weak self] in
                self?.onTileActivated?(tileID)
            }
            if previewView.superview !== hostView {
                hostView.addSubview(previewView)
            }

            tileView.setAccessibilityElement(false)
            previewView.showLiveTile(tileView)
        }
    }

    func layoutPreview(
        for tileID: UUID,
        previewFrame: NSRect,
        contentSize: NSSize
    ) {
        guard let previewView = previewViews[tileID] else { return }
        previewView.isHidden = false
        previewView.contentSize = contentSize
        previewView.frame = previewFrame
    }

    func hidePreview(for tileID: UUID) {
        previewViews[tileID]?.isHidden = true
    }

    private func teardownOverview(
        tileViews: [UUID: WorkspaceTileHostView],
        hostView: NSView
    ) {
        for previewView in previewViews.values {
            previewView.restoreLiveTile(into: hostView)
            previewView.removeFromSuperview()
        }

        for tileView in tileViews.values {
            tileView.setAccessibilityElement(true)
            tileView.isHidden = false
            if tileView.superview !== hostView {
                tileView.removeFromSuperview()
                hostView.addSubview(tileView)
            }
        }
    }

    private func makePreviewView(for tileID: UUID) -> WorkspaceCanvasOverviewTilePreviewView {
        let previewView = WorkspaceCanvasOverviewTilePreviewView(tileID: tileID)
        previewViews[tileID] = previewView
        return previewView
    }
}

@MainActor
private final class WorkspaceCanvasOverviewTilePreviewView: NSView {
    private enum Metrics {
        static let cornerRadius: CGFloat = 16
        static let compactCornerRadius: CGFloat = 8
        static let compactCornerRadiusThreshold: CGFloat = 260
    }

    let tileID: UUID
    let liveContainerView = NSView()
    let clickOverlayView = WorkspaceCanvasOverviewClickOverlayView()

    var onPrimaryClick: (() -> Void)?

    var contentSize: NSSize = .zero {
        didSet {
            guard oldValue != contentSize else { return }
            needsLayout = true
        }
    }

    private weak var liveTileView: WorkspaceTileHostView?

    override var isFlipped: Bool { true }

    init(tileID: UUID) {
        self.tileID = tileID
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Metrics.cornerRadius
        layer?.masksToBounds = true

        liveContainerView.wantsLayer = true
        liveContainerView.layer?.anchorPoint = CGPoint(x: 0, y: 0)
        liveContainerView.layer?.isGeometryFlipped = true

        clickOverlayView.onPrimaryClick = { [weak self] in
            self?.onPrimaryClick?()
        }
        configureAccessibility(
            identifier: TairiAccessibility.tile(tileID),
            label: "Workspace tile overview",
            value: "overview"
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = effectiveCornerRadius()
        clickOverlayView.frame = bounds

        let contentFrame = NSRect(origin: .zero, size: contentSize)
        liveContainerView.frame = contentFrame
        liveTileView?.frame = contentFrame

        let scaleX = contentSize.width > 0 ? bounds.width / contentSize.width : 1
        let scaleY = contentSize.height > 0 ? bounds.height / contentSize.height : 1
        liveContainerView.layer?.setAffineTransform(CGAffineTransform(scaleX: scaleX, y: scaleY))
    }

    func showLiveTile(_ tileView: WorkspaceTileHostView) {
        if liveContainerView.superview !== self {
            addSubview(liveContainerView)
        }
        if tileView.superview !== liveContainerView {
            tileView.removeFromSuperview()
            liveContainerView.addSubview(tileView)
        }
        tileView.isHidden = false
        liveTileView = tileView
        ensureClickOverlayIsOnTop()
        needsLayout = true
    }

    func restoreLiveTile(into hostView: NSView) {
        if let liveTileView {
            liveTileView.removeFromSuperview()
            hostView.addSubview(liveTileView)
            liveTileView.isHidden = false
            self.liveTileView = nil
        }
        liveContainerView.removeFromSuperview()
        clickOverlayView.removeFromSuperview()
    }

    private func ensureClickOverlayIsOnTop() {
        if clickOverlayView.superview !== self {
            addSubview(clickOverlayView)
            return
        }
        addSubview(clickOverlayView, positioned: .above, relativeTo: nil)
    }

    private func effectiveCornerRadius() -> CGFloat {
        let compactDimension = min(bounds.width, bounds.height)
        return compactDimension < Metrics.compactCornerRadiusThreshold
            ? Metrics.compactCornerRadius
            : Metrics.cornerRadius
    }
}

@MainActor
private final class WorkspaceCanvasOverviewClickOverlayView: NSView {
    var onPrimaryClick: (() -> Void)?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        onPrimaryClick?()
    }
}

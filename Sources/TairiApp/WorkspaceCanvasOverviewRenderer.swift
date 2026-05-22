import AppKit

@MainActor
final class WorkspaceCanvasOverviewRenderer {
    var onTileActivated: ((UUID) -> Void)?

    private var previewViews: [UUID: WorkspaceCanvasOverviewTilePreviewView] = [:]

    func sync(
        tileViews: [UUID: WorkspaceTileHostView],
        allTileIDs: Set<UUID>,
        isOverviewPresented: Bool,
        selectedTileID: UUID?,
        theme: GhosttyAppTheme,
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
            previewView.updateSelectionAppearance(
                isSelected: tileID == selectedTileID,
                theme: theme
            )
            previewView.updateLabel(tileView.overviewLabel, theme: theme)
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
    private enum LabelMetrics {
        static let horizontalPadding: CGFloat = 24
        static let minWidth: CGFloat = 172
        static let maxWidthFraction: CGFloat = 0.86
        static let height: CGFloat = 54
        static let fontSize: CGFloat = 20
        static let minimumFontSize: CGFloat = 11
    }

    let tileID: UUID
    let liveContainerView = NSView()
    let selectionOverlayView = NSView()
    let labelChromeView: NSView
    let labelContentView = NSView()
    let labelField = NSTextField(labelWithString: "")
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
        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.style = .regular
            glassView.tintColor = NSColor.white.withAlphaComponent(0.18)
            labelChromeView = glassView
        } else {
            labelChromeView = NSView()
        }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = WorkspaceTileChromeMetrics.cornerRadius
        layer?.masksToBounds = true

        liveContainerView.wantsLayer = true
        liveContainerView.layer?.anchorPoint = CGPoint(x: 0, y: 0)
        liveContainerView.layer?.isGeometryFlipped = true
        selectionOverlayView.wantsLayer = true
        selectionOverlayView.isHidden = true
        labelChromeView.wantsLayer = true
        labelChromeView.layer?.masksToBounds = false
        labelChromeView.layer?.shadowColor = NSColor.black.cgColor
        labelChromeView.layer?.shadowOpacity = 0.24
        labelChromeView.layer?.shadowRadius = 18
        labelChromeView.layer?.shadowOffset = CGSize(width: 0, height: 8)
        labelContentView.wantsLayer = true
        labelField.alignment = .center
        labelField.font = .systemFont(ofSize: LabelMetrics.fontSize, weight: .bold)
        labelField.lineBreakMode = .byClipping
        labelField.maximumNumberOfLines = 1
        labelContentView.addSubview(labelField)
        if #available(macOS 26.0, *), let glassView = labelChromeView as? NSGlassEffectView {
            glassView.contentView = labelContentView
        } else {
            labelChromeView.addSubview(labelContentView)
        }

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
        let cornerRadius = effectiveCornerRadius()
        layer?.cornerRadius = cornerRadius
        clickOverlayView.frame = bounds
        selectionOverlayView.frame = bounds
        selectionOverlayView.layer?.cornerRadius = cornerRadius

        let contentFrame = NSRect(origin: .zero, size: contentSize)
        liveContainerView.frame = contentFrame
        liveTileView?.frame = contentFrame

        let scaleX = contentSize.width > 0 ? bounds.width / contentSize.width : 1
        let scaleY = contentSize.height > 0 ? bounds.height / contentSize.height : 1
        liveContainerView.layer?.setAffineTransform(CGAffineTransform(scaleX: scaleX, y: scaleY))
        layoutLabel()
    }

    func updateSelectionAppearance(isSelected: Bool, theme: GhosttyAppTheme) {
        layer?.borderColor = theme.tileInactiveBorder.cgColor
        layer?.borderWidth = 1
        let accentBorderWidth = min(max(min(bounds.width, bounds.height) * 0.012, 4), 8)
        selectionOverlayView.isHidden = !isSelected
        selectionOverlayView.layer?.backgroundColor =
            theme.accent
            .withAlphaComponent(theme.isLightTheme ? 0.08 : 0.12)
            .cgColor
        selectionOverlayView.layer?.borderColor = theme.tileActiveBorder.cgColor
        selectionOverlayView.layer?.borderWidth = isSelected ? accentBorderWidth : 0
        needsLayout = true
    }

    func updateLabel(_ label: String, theme: GhosttyAppTheme) {
        labelField.stringValue = label
        labelField.textColor = theme.primaryText
        if #available(macOS 26.0, *), let glassView = labelChromeView as? NSGlassEffectView {
            glassView.tintColor = theme.accent.withAlphaComponent(theme.isLightTheme ? 0.16 : 0.22)
        } else {
            labelContentView.layer?.backgroundColor =
                theme.cardBackground
                .withAlphaComponent(theme.isLightTheme ? 0.94 : 0.88)
                .cgColor
            labelContentView.layer?.borderColor = theme.divider.withAlphaComponent(0.9).cgColor
            labelContentView.layer?.borderWidth = 1
        }
        setAccessibilityLabel("Workspace tile \(label)")
        needsLayout = true
    }

    func showLiveTile(_ tileView: WorkspaceTileHostView) {
        if liveContainerView.superview !== self {
            addSubview(liveContainerView)
        }
        if selectionOverlayView.superview !== self {
            addSubview(selectionOverlayView, positioned: .above, relativeTo: liveContainerView)
        }
        if labelChromeView.superview !== self {
            addSubview(labelChromeView, positioned: .above, relativeTo: selectionOverlayView)
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
        selectionOverlayView.removeFromSuperview()
        labelChromeView.removeFromSuperview()
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
        WorkspaceTileChromeMetrics.cornerRadius(for: bounds.size)
    }

    private func layoutLabel() {
        let maxWidth = max(bounds.width * LabelMetrics.maxWidthFraction, 64)
        let minWidth = min(LabelMetrics.minWidth, maxWidth)
        let maxTextWidth = max(maxWidth - (LabelMetrics.horizontalPadding * 2), 1)
        let font = fittedLabelFont(maxTextWidth: maxTextWidth)
        labelField.font = font
        let textWidth = labelWidth(using: font)
        let width = min(max(textWidth + (LabelMetrics.horizontalPadding * 2), minWidth), maxWidth)
        let height = min(LabelMetrics.height, max(bounds.height - 24, 36))
        labelChromeView.frame = NSRect(
            x: floor((bounds.width - width) / 2),
            y: floor((bounds.height - height) / 2),
            width: width,
            height: height
        )
        labelContentView.frame = labelChromeView.bounds
        labelContentView.layer?.cornerRadius = height / 2
        labelContentView.layer?.masksToBounds = true
        labelChromeView.layer?.cornerRadius = height / 2
        labelChromeView.layer?.shadowPath = CGPath(
            roundedRect: labelChromeView.bounds,
            cornerWidth: height / 2,
            cornerHeight: height / 2,
            transform: nil
        )
        if #available(macOS 26.0, *), let glassView = labelChromeView as? NSGlassEffectView {
            glassView.cornerRadius = height / 2
        }
        labelField.frame = NSRect(
            x: LabelMetrics.horizontalPadding,
            y: floor((height - font.pointSize - 2) / 2),
            width: max(width - (LabelMetrics.horizontalPadding * 2), 1),
            height: ceil(font.pointSize + 4)
        )
    }

    private func fittedLabelFont(maxTextWidth: CGFloat) -> NSFont {
        var fontSize = LabelMetrics.fontSize
        while fontSize > LabelMetrics.minimumFontSize {
            let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            if labelWidth(using: font) <= maxTextWidth {
                return font
            }
            fontSize -= 1
        }
        return NSFont.systemFont(ofSize: LabelMetrics.minimumFontSize, weight: .bold)
    }

    private func labelWidth(using font: NSFont) -> CGFloat {
        let text = labelField.stringValue as NSString
        return ceil(
            text.size(withAttributes: [.font: font]).width
        )
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

import AppKit

@MainActor
final class WorkspaceClosingSnapshotView: NSImageView {
    override var isFlipped: Bool { true }

    init(image: NSImage) {
        super.init(frame: .zero)
        self.image = image
        imageScaling = .scaleAxesIndependently
        imageAlignment = .alignCenter
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

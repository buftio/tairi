import AppKit
import SwiftUI

struct EmptyWorkspaceTitleInteractionView: NSViewRepresentable {
    let accessibilityLabel: String
    let onRenameRequest: () -> Void

    func makeNSView(context: Context) -> EmptyWorkspaceTitleInteractionNSView {
        let view = EmptyWorkspaceTitleInteractionNSView()
        view.onRenameRequest = onRenameRequest
        view.configureAccessibility(
            identifier: TairiAccessibility.emptyWorkspaceTitle,
            label: accessibilityLabel,
            role: .button
        )
        return view
    }

    func updateNSView(_ nsView: EmptyWorkspaceTitleInteractionNSView, context: Context) {
        nsView.onRenameRequest = onRenameRequest
        nsView.setAccessibilityIdentifier(TairiAccessibility.emptyWorkspaceTitle)
        nsView.setAccessibilityLabel(accessibilityLabel)
    }
}

final class EmptyWorkspaceTitleInteractionNSView: NSView {
    var onRenameRequest: (() -> Void)?

    private var didTriggerDeepClick = false

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        pressureConfiguration = NSPressureConfiguration(pressureBehavior: .primaryDeepClick)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        didTriggerDeepClick = false
        if event.clickCount >= 2 {
            onRenameRequest?()
            return
        }
        super.mouseDown(with: event)
    }

    override func pressureChange(with event: NSEvent) {
        super.pressureChange(with: event)

        guard !didTriggerDeepClick, event.stage >= 2 else { return }
        didTriggerDeepClick = true
        onRenameRequest?()
    }

    override func mouseUp(with event: NSEvent) {
        didTriggerDeepClick = false
        super.mouseUp(with: event)
    }
}

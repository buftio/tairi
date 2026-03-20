import AppKit
import SwiftUI

struct WorkspaceRowInteractionView: NSViewRepresentable {
    let accessibilityIdentifier: String
    let accessibilityLabel: String
    let onClick: () -> Void
    let onRenameRequest: () -> Void

    func makeNSView(context: Context) -> WorkspaceRowInteractionNSView {
        let view = WorkspaceRowInteractionNSView()
        view.onClick = onClick
        view.onRenameRequest = onRenameRequest
        view.configureAccessibility(
            identifier: accessibilityIdentifier,
            label: accessibilityLabel,
            role: .button
        )
        return view
    }

    func updateNSView(_ nsView: WorkspaceRowInteractionNSView, context: Context) {
        nsView.onClick = onClick
        nsView.onRenameRequest = onRenameRequest
        nsView.setAccessibilityIdentifier(accessibilityIdentifier)
        nsView.setAccessibilityLabel(accessibilityLabel)
    }
}

final class WorkspaceRowInteractionNSView: NSView {
    var onClick: (() -> Void)?
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

        onClick?()
    }

    override func mouseUp(with event: NSEvent) {
        didTriggerDeepClick = false
        super.mouseUp(with: event)
    }

    override func pressureChange(with event: NSEvent) {
        super.pressureChange(with: event)

        guard !didTriggerDeepClick, event.stage >= 2 else { return }
        didTriggerDeepClick = true
        onRenameRequest?()
    }
}

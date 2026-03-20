import AppKit
import SwiftUI

private let workspaceRowDragType = NSPasteboard.PasteboardType("dev.tairi.workspace-row")

struct WorkspaceRowInteractionView: NSViewRepresentable {
    let workspaceID: UUID
    let accessibilityIdentifier: String
    let accessibilityLabel: String
    let onClick: () -> Void
    let onIconClick: () -> Void
    let onRenameRequest: () -> Void
    let onReorderHover: (UUID, WorkspaceStore.WorkspaceDropPosition) -> Void
    let onReorderHoverEnd: () -> Void
    let onReorderRequest: (UUID, WorkspaceStore.WorkspaceDropPosition) -> Void

    func makeNSView(context: Context) -> WorkspaceRowInteractionNSView {
        let view = WorkspaceRowInteractionNSView()
        view.workspaceID = workspaceID
        view.onClick = onClick
        view.onIconClick = onIconClick
        view.onRenameRequest = onRenameRequest
        view.onReorderHover = onReorderHover
        view.onReorderHoverEnd = onReorderHoverEnd
        view.onReorderRequest = onReorderRequest
        view.configureAccessibility(
            identifier: accessibilityIdentifier,
            label: accessibilityLabel,
            role: .button
        )
        return view
    }

    func updateNSView(_ nsView: WorkspaceRowInteractionNSView, context: Context) {
        nsView.workspaceID = workspaceID
        nsView.onClick = onClick
        nsView.onIconClick = onIconClick
        nsView.onRenameRequest = onRenameRequest
        nsView.onReorderHover = onReorderHover
        nsView.onReorderHoverEnd = onReorderHoverEnd
        nsView.onReorderRequest = onReorderRequest
        nsView.setAccessibilityIdentifier(accessibilityIdentifier)
        nsView.setAccessibilityLabel(accessibilityLabel)
    }
}

final class WorkspaceRowInteractionNSView: NSView, NSDraggingSource {
    var workspaceID: UUID?
    var onClick: (() -> Void)?
    var onIconClick: (() -> Void)?
    var onRenameRequest: (() -> Void)?
    var onReorderHover: ((UUID, WorkspaceStore.WorkspaceDropPosition) -> Void)?
    var onReorderHoverEnd: (() -> Void)?
    var onReorderRequest: ((UUID, WorkspaceStore.WorkspaceDropPosition) -> Void)?

    private var didTriggerDeepClick = false
    private var mouseDownPoint: NSPoint?
    private var isDraggingRow = false

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        pressureConfiguration = NSPressureConfiguration(pressureBehavior: .primaryDeepClick)
        registerForDraggedTypes([workspaceRowDragType])
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
        isDraggingRow = false
        mouseDownPoint = convert(event.locationInWindow, from: nil)

        if event.clickCount >= 2 {
            onRenameRequest?()
            return
        }

        if isWithinIconHitArea(mouseDownPoint ?? .zero) {
            onIconClick?()
            return
        }

        onClick?()
    }

    override func mouseUp(with event: NSEvent) {
        didTriggerDeepClick = false
        isDraggingRow = false
        mouseDownPoint = nil
        super.mouseUp(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownPoint, !isDraggingRow, let workspaceID else {
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        let deltaX = location.x - mouseDownPoint.x
        let deltaY = location.y - mouseDownPoint.y
        let dragDistance = hypot(deltaX, deltaY)
        guard dragDistance >= 4 else { return }

        isDraggingRow = true

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(workspaceID.uuidString, forType: workspaceRowDragType)
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: dragPreviewImage())
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func pressureChange(with event: NSEvent) {
        super.pressureChange(with: event)

        guard !didTriggerDeepClick, event.stage >= 2 else { return }
        didTriggerDeepClick = true
        onRenameRequest?()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateReorderHover(using: sender)
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateReorderHover(using: sender)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onReorderHoverEnd?()
        super.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let targetWorkspaceID = workspaceID,
              let draggedWorkspaceID = draggedWorkspaceID(from: sender) else {
            return false
        }
        return draggedWorkspaceID != targetWorkspaceID
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        updateReorderTarget(using: sender)
        onReorderHoverEnd?()
        return true
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        onReorderHoverEnd?()
    }

    private func updateReorderTarget(using draggingInfo: NSDraggingInfo) {
        guard let targetWorkspaceID = workspaceID,
              let draggedWorkspaceID = draggedWorkspaceID(from: draggingInfo),
              draggedWorkspaceID != targetWorkspaceID
        else {
            return
        }

        let localPoint = convert(draggingInfo.draggingLocation, from: nil)
        let position: WorkspaceStore.WorkspaceDropPosition = localPoint.y > bounds.midY ? .before : .after
        onReorderRequest?(draggedWorkspaceID, position)
    }

    private func updateReorderHover(using draggingInfo: NSDraggingInfo) {
        guard let targetWorkspaceID = workspaceID,
              let draggedWorkspaceID = draggedWorkspaceID(from: draggingInfo),
              draggedWorkspaceID != targetWorkspaceID
        else {
            onReorderHoverEnd?()
            return
        }

        let localPoint = convert(draggingInfo.draggingLocation, from: nil)
        let position: WorkspaceStore.WorkspaceDropPosition = localPoint.y > bounds.midY ? .before : .after
        onReorderHover?(targetWorkspaceID, position)
    }

    private func draggedWorkspaceID(from draggingInfo: NSDraggingInfo) -> UUID? {
        let pasteboard = draggingInfo.draggingPasteboard
        guard let rawValue = pasteboard.string(forType: workspaceRowDragType) else {
            return nil
        }
        return UUID(uuidString: rawValue)
    }

    private func dragPreviewImage() -> NSImage {
        let size = NSSize(width: max(bounds.width, 1), height: max(bounds.height, 1))
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 8, yRadius: 8).fill()
        image.unlockFocus()
        return image
    }

    private func isWithinIconHitArea(_ point: NSPoint) -> Bool {
        let hitRect = NSRect(x: 8, y: 6, width: 28, height: max(bounds.height - 12, 16))
        return hitRect.contains(point)
    }
}

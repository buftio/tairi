import AppKit
import SwiftUI

@MainActor
final class WorkspaceTileContentHostingView<Content: View>: NSHostingView<Content> {
    var onPerformShortcut: ((NSEvent) -> Bool)?
    var consumesHorizontalScrollWheel = false

    override func scrollWheel(with event: NSEvent) {
        if consumesHorizontalScrollWheel,
            Self.shouldConsumeHorizontalScrollWheel(
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY
            )
        {
            return
        }
        super.scrollWheel(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onPerformShortcut?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    static func shouldConsumeHorizontalScrollWheel(deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        let horizontalDelta = abs(deltaX)
        guard horizontalDelta > 0 else { return false }
        return horizontalDelta >= abs(deltaY)
    }
}

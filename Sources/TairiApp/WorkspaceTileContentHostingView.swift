import AppKit
import SwiftUI

@MainActor
final class WorkspaceTileContentHostingView<Content: View>: NSHostingView<Content> {
    var onPerformShortcut: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onPerformShortcut?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

import AppKit
import XCTest

@testable import TairiApp

@MainActor
final class WorkspaceTileHeaderInteractionViewTests: XCTestCase {
    func testMouseDownDoesNotSelectUntilMouseUp() throws {
        let view = WorkspaceTileHeaderInteractionView(frame: NSRect(x: 0, y: 0, width: 120, height: 34))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView?.addSubview(view)

        var selectCount = 0
        view.onSelect = {
            selectCount += 1
        }

        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: NSPoint(x: 10, y: 10), window: window))

        XCTAssertEqual(selectCount, 0)

        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, location: NSPoint(x: 10, y: 10), window: window))

        XCTAssertEqual(selectCount, 1)
    }

    private func mouseEvent(type: NSEvent.EventType, location: NSPoint, window: NSWindow) throws -> NSEvent {
        let event = NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )

        return try XCTUnwrap(event)
    }
}

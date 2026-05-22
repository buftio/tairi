import AppKit
import XCTest

@testable import TairiApp

@MainActor
final class WorkspaceRenameFieldTests: XCTestCase {
    func testFocusForRenamePreservesExistingSelection() throws {
        let textField = makeFocusedTextField(stringValue: "Alpha")
        let editor = try XCTUnwrap(textField.currentEditor() as? NSTextView)
        editor.selectedRange = NSRange(location: 2, length: 0)

        textField.focusForRenameIfNeeded()

        XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 0))
    }

    func testPlaceCursorAtEndUsesUTF16Length() throws {
        let textField = makeFocusedTextField(stringValue: "A😀B")

        textField.placeCursorAtEnd()

        let editor = try XCTUnwrap(textField.currentEditor() as? NSTextView)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 4, length: 0))
    }

    private func makeFocusedTextField(stringValue: String) -> WorkspaceRenameTextField {
        let textField = WorkspaceRenameTextField(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        textField.stringValue = stringValue

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView?.addSubview(textField)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textField)

        return textField
    }
}

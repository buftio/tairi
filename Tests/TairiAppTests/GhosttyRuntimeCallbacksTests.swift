import GhosttyDyn
import XCTest

@testable import TairiApp

@MainActor
final class GhosttyRuntimeCallbacksTests: XCTestCase {
    func testWriteClipboardStandardWritesStandardLocation() {
        let payload = clipboardWritePayload("standard-value", location: GHOSTTY_CLIPBOARD_STANDARD)

        XCTAssertEqual(payload?.location.rawValue, GHOSTTY_CLIPBOARD_STANDARD.rawValue)
        XCTAssertEqual(payload?.value, "standard-value")
    }

    func testWriteClipboardSelectionWritesSelectionLocation() {
        let payload = clipboardWritePayload("selection-value", location: GHOSTTY_CLIPBOARD_SELECTION)

        XCTAssertEqual(payload?.location.rawValue, GHOSTTY_CLIPBOARD_SELECTION.rawValue)
        XCTAssertEqual(payload?.value, "selection-value")
    }

    private func clipboardWritePayload(
        _ value: String,
        location: ghostty_clipboard_e
    ) -> (location: ghostty_clipboard_e, value: String)? {
        value.withCString { valuePointer in
            "text/plain".withCString { mimePointer in
                var content = ghostty_clipboard_content_s(mime: mimePointer, data: valuePointer)
                return withUnsafePointer(to: &content) { pointer in
                    GhosttyRuntime.clipboardWritePayload(
                        location: location,
                        content: pointer,
                        len: 1
                    )
                }
            }
        }
    }
}

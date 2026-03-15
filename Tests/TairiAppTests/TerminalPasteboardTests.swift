import AppKit
import XCTest
@testable import TairiApp

final class TerminalPasteboardTests: XCTestCase {
    func testPreferredPasteStringReturnsEscapedFilePath() throws {
        let pasteboard = NSPasteboard(name: .init("tairi.tests.pasteboard.\(UUID().uuidString)"))
        pasteboard.clearContents()

        let url = URL(fileURLWithPath: "/tmp/hello world/image (1).png")
        XCTAssertTrue(pasteboard.writeObjects([url as NSURL]))

        XCTAssertEqual(
            TerminalPasteboard.preferredPasteString(from: pasteboard),
            #"/tmp/hello\ world/image\ \(1\).png"#
        )
    }

    func testPreferredPasteStringJoinsMultipleURLs() throws {
        let pasteboard = NSPasteboard(name: .init("tairi.tests.pasteboard.\(UUID().uuidString)"))
        pasteboard.clearContents()

        let urls = [
            URL(fileURLWithPath: "/tmp/one.png"),
            URL(string: "https://example.com/two.png")!,
        ]
        XCTAssertTrue(pasteboard.writeObjects(urls as [NSURL]))

        XCTAssertEqual(
            TerminalPasteboard.preferredPasteString(from: pasteboard),
            "/tmp/one.png https://example.com/two.png"
        )
    }

    func testPreferredPasteStringFallsBackToPlainText() {
        let pasteboard = NSPasteboard(name: .init("tairi.tests.pasteboard.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)

        XCTAssertEqual(TerminalPasteboard.preferredPasteString(from: pasteboard), "hello")
    }

    func testPreferredPasteStringMaterializesClipboardImage() {
        let pasteboard = NSPasteboard(name: .init("tairi.tests.pasteboard.\(UUID().uuidString)"))
        pasteboard.clearContents()

        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()

        XCTAssertTrue(pasteboard.writeObjects([image]))

        guard let escapedPath = TerminalPasteboard.preferredPasteString(from: pasteboard) else {
            return XCTFail("expected image path")
        }

        let path = escapedPath.replacingOccurrences(of: "\\ ", with: " ")
        XCTAssertTrue(path.hasSuffix(".png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testPreferredPasteStringReturnsNilWhenClipboardUnsupported() {
        let pasteboard = NSPasteboard(name: .init("tairi.tests.pasteboard.\(UUID().uuidString)"))
        pasteboard.clearContents()

        XCTAssertNil(TerminalPasteboard.preferredPasteString(from: pasteboard))
    }
}

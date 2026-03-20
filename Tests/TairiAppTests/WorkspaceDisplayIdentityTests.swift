import AppKit
import XCTest
@testable import TairiApp

@MainActor
final class WorkspaceDisplayIdentityTests: XCTestCase {
    func testEmptyStateBrandingFallsBackToDefaultWithoutAssignedFolder() {
        let workspace = WorkspaceStore.Workspace(title: WorkspaceStore.automaticStripTitle(index: 1))
        let defaultIcon = NSImage(size: NSSize(width: 8, height: 8))

        let branding = WorkspaceDisplayIdentity.emptyStateBranding(
            for: workspace,
            defaultIcon: defaultIcon
        )

        XCTAssertNil(branding.title)
        XCTAssertFalse(branding.usesWorkspaceIdentity)
        guard case let .image(icon)? = branding.icon else {
            return XCTFail("Expected default image branding")
        }
        XCTAssertEqual(icon, defaultIcon)
    }

    func testEmptyStateTitleUsesUntitledStripForAutomaticWorkspaceWithoutFolder() {
        let workspace = WorkspaceStore.Workspace(title: WorkspaceStore.automaticStripTitle(index: 1))

        XCTAssertEqual(
            WorkspaceDisplayIdentity.emptyStateTitle(for: workspace),
            WorkspaceDisplayIdentity.untitledStripTitle
        )
    }

    func testEmptyStateTitleUsesCustomWorkspaceNameWithoutFolder() {
        let workspace = WorkspaceStore.Workspace(
            title: "Inbox",
            folderPath: nil,
            usesAutomaticTitle: false
        )

        XCTAssertEqual(WorkspaceDisplayIdentity.emptyStateTitle(for: workspace), "Inbox")
    }

    func testEmptyStateBrandingUsesWorkspaceIdentityForAssignedFolder() throws {
        let directory = try makeTemporaryDirectory(named: "Inbox")
        defer { try? FileManager.default.removeItem(atPath: directory) }

        let workspace = WorkspaceStore.Workspace(
            title: "Inbox",
            folderPath: directory,
            usesAutomaticTitle: true
        )

        let branding = WorkspaceDisplayIdentity.emptyStateBranding(
            for: workspace,
            defaultIcon: nil
        )

        XCTAssertEqual(branding.title, "Inbox")
        XCTAssertTrue(branding.usesWorkspaceIdentity)
        XCTAssertNotNil(branding.icon)
    }

    func testEmptyStateBrandingUsesCustomSymbolWithoutAssignedFolder() {
        let workspace = WorkspaceStore.Workspace(
            title: WorkspaceStore.automaticStripTitle(index: 1),
            iconSymbolName: "terminal"
        )

        let branding = WorkspaceDisplayIdentity.emptyStateBranding(
            for: workspace,
            defaultIcon: nil
        )

        XCTAssertEqual(branding.title, WorkspaceDisplayIdentity.untitledStripTitle)
        XCTAssertTrue(branding.usesWorkspaceIdentity)
        guard case let .symbol(symbolName)? = branding.icon else {
            return XCTFail("Expected symbol branding")
        }
        XCTAssertEqual(symbolName, "terminal")
    }

    func testEmptyStateBrandingPrefersCustomImageFileOverSymbolAndFolder() throws {
        let directory = try makeTemporaryDirectory(named: "Inbox")
        let iconURL = URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent("strip-icon.png", isDirectory: false)
        try writeTestPNG(to: iconURL)
        defer { try? FileManager.default.removeItem(atPath: directory) }

        let workspace = WorkspaceStore.Workspace(
            title: "Inbox",
            folderPath: directory,
            iconSymbolName: "terminal",
            iconFilePath: iconURL.path(percentEncoded: false),
            usesAutomaticTitle: true
        )

        let branding = WorkspaceDisplayIdentity.emptyStateBranding(
            for: workspace,
            defaultIcon: nil
        )

        XCTAssertEqual(branding.title, "Inbox")
        XCTAssertTrue(branding.usesWorkspaceIdentity)
        guard case .image? = branding.icon else {
            return XCTFail("Expected image branding")
        }
    }

    private func makeTemporaryDirectory(named name: String) throws -> String {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.path(percentEncoded: false)
    }

    private func writeTestPNG(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.systemTeal.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 16, height: 16)).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            XCTFail("Failed to create test PNG data")
            return
        }

        try pngData.write(to: url)
    }
}

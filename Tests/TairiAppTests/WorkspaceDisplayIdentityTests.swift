import AppKit
import XCTest
@testable import TairiApp

@MainActor
final class WorkspaceDisplayIdentityTests: XCTestCase {
    func testEmptyStateBrandingFallsBackToDefaultWithoutAssignedFolder() {
        let workspace = WorkspaceStore.Workspace(title: "01")
        let defaultIcon = NSImage(size: NSSize(width: 8, height: 8))

        let branding = WorkspaceDisplayIdentity.emptyStateBranding(
            for: workspace,
            defaultIcon: defaultIcon
        )

        XCTAssertNil(branding.title)
        XCTAssertFalse(branding.usesWorkspaceIdentity)
        XCTAssertEqual(branding.icon, defaultIcon)
    }

    func testEmptyStateTitleUsesUntitledStripForAutomaticWorkspaceWithoutFolder() {
        let workspace = WorkspaceStore.Workspace(title: "01")

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

    private func makeTemporaryDirectory(named name: String) throws -> String {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.path(percentEncoded: false)
    }
}

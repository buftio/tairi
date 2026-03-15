import AppKit
import Foundation

enum TairiAccessibility {
    static let appRoot = "app-root"
    static let workspaceSidebar = "workspace-sidebar"
    static let workspaceList = "workspace-list"
    static let mainPanel = "main-panel"
    static let workspaceTitle = "workspace-title"
    static let workspaceCanvas = "workspace-canvas"
    static let widthPicker = "tile-width-picker"
    static let newTileButton = "new-tile-button"
    static let previousWorkspaceButton = "previous-workspace-button"
    static let nextWorkspaceButton = "next-workspace-button"
    static let runtimeError = "runtime-error"

    static func workspaceButton(_ title: String) -> String {
        "workspace-button-\(title)"
    }

    static func tile(_ tileID: UUID) -> String {
        "workspace-tile-\(tileID.uuidString.lowercased())"
    }

    static func tileTitle(_ tileID: UUID) -> String {
        "workspace-tile-title-\(tileID.uuidString.lowercased())"
    }

    static func tilePath(_ tileID: UUID) -> String {
        "workspace-tile-path-\(tileID.uuidString.lowercased())"
    }

    static func tileSurface(_ tileID: UUID) -> String {
        "workspace-tile-surface-\(tileID.uuidString.lowercased())"
    }

    static func tileResizeHandle(_ tileID: UUID) -> String {
        "workspace-tile-resize-handle-\(tileID.uuidString.lowercased())"
    }
}

enum TairiEnvironment {
    static let isUITesting = ProcessInfo.processInfo.environment["TAIRI_UI_TEST"] == "1"
}

extension NSView {
    func configureAccessibility(
        identifier: String,
        label: String,
        role: NSAccessibility.Role = .group,
        value: String? = nil
    ) {
        setAccessibilityElement(true)
        setAccessibilityIdentifier(identifier)
        setAccessibilityLabel(label)
        setAccessibilityRole(role)
        if let value {
            setAccessibilityValue(value)
        }
    }
}

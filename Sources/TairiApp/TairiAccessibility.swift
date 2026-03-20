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
    static let toggleSidebarButton = "toggle-sidebar-button"
    static let zoomOutOverviewButton = "zoom-out-overview-button"
    static let tileSpotlight = "tile-spotlight"
    static let tileSpotlightSearchField = "tile-spotlight-search-field"
    static let tileSpotlightResults = "tile-spotlight-results"
    static let runtimeError = "runtime-error"
    static let emptyWorkspaceState = "empty-workspace-state"
    static let emptyWorkspaceTitle = "empty-workspace-title"
    static let emptyWorkspaceCreateTileHint = "empty-workspace-create-tile-hint"
    static let emptyWorkspaceToggleSidebarHint = "empty-workspace-toggle-sidebar-hint"
    static let emptyWorkspaceKeyboardShortcutsHint = "empty-workspace-keyboard-shortcuts-hint"
    static let emptyWorkspaceAddFolderButton = "empty-workspace-add-folder-button"
    static let emptyWorkspaceChooseIconButton = "empty-workspace-choose-icon-button"

    static func workspaceButton(_ workspaceID: UUID) -> String {
        "workspace-button-\(workspaceID.uuidString.lowercased())"
    }

    static func workspaceRenameField(_ workspaceID: UUID) -> String {
        "workspace-rename-field-\(workspaceID.uuidString.lowercased())"
    }

    static func workspaceDropIndicator(
        _ workspaceID: UUID,
        position: WorkspaceStore.WorkspaceDropPosition
    ) -> String {
        let suffix: String
        switch position {
        case .before:
            suffix = "before"
        case .after:
            suffix = "after"
        }
        return "workspace-drop-indicator-\(suffix)-\(workspaceID.uuidString.lowercased())"
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

    static func tileCloseButton(_ tileID: UUID) -> String {
        "workspace-tile-close-button-\(tileID.uuidString.lowercased())"
    }

    static func tileResizeHandle(_ tileID: UUID) -> String {
        "workspace-tile-resize-handle-\(tileID.uuidString.lowercased())"
    }

    static func tileSpotlightResult(_ tileID: UUID) -> String {
        "tile-spotlight-result-\(tileID.uuidString.lowercased())"
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

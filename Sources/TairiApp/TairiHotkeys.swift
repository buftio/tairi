import AppKit
import SwiftUI

struct TairiHotkey {
    let key: TairiHotkeyKey
    let modifiers: EventModifiers

    var keyEquivalent: KeyEquivalent {
        key.keyEquivalent
    }

    var eventModifiers: NSEvent.ModifierFlags {
        modifiers.nsEventModifiers
    }

    var displayLabel: String {
        "\(modifiers.displayPrefix)\(key.displayLabel)"
    }

    var displayTokens: [String] {
        modifiers.displayTokens + [key.displayLabel]
    }

    func matches(_ event: NSEvent) -> Bool {
        let activeModifiers = event.modifierFlags.intersection(.tairiShortcutRelevant)
        guard activeModifiers == modifiers.nsEventModifiers else { return false }
        return key.matches(event)
    }
}

struct TairiHotkeyReference: Identifiable {
    let id: String
    let title: String
    let hotkey: TairiHotkey
}

struct TairiHotkeySection: Identifiable {
    let id: String
    let title: String
    let entries: [TairiHotkeyReference]
}

enum TairiHotkeyKey {
    case character(Character)
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow

    var keyEquivalent: KeyEquivalent {
        switch self {
        case .character(let character):
            KeyEquivalent(character)
        case .leftArrow:
            .leftArrow
        case .rightArrow:
            .rightArrow
        case .upArrow:
            .upArrow
        case .downArrow:
            .downArrow
        }
    }

    var displayLabel: String {
        switch self {
        case .character(let character):
            String(character).uppercased()
        case .leftArrow:
            "←"
        case .rightArrow:
            "→"
        case .upArrow:
            "↑"
        case .downArrow:
            "↓"
        }
    }

    func matches(_ event: NSEvent) -> Bool {
        switch self {
        case .character(let character):
            event.charactersIgnoringModifiers?.lowercased() == String(character).lowercased()
        case .leftArrow:
            event.keyCode == 123
        case .rightArrow:
            event.keyCode == 124
        case .upArrow:
            event.keyCode == 126
        case .downArrow:
            event.keyCode == 125
        }
    }
}

enum TairiHotkeys {
    static let tileReorderModifiers: EventModifiers = [.command, .option, .shift]
    static let openAppSettings = TairiHotkey(
        key: .character("."),
        modifiers: [.command]
    )
    static let openGhosttySettings = TairiHotkey(
        key: .character(","),
        modifiers: [.command, .option]
    )
    static let reloadGhosttyConfiguration = TairiHotkey(
        key: .character(","),
        modifiers: [.command, .shift]
    )
    static let searchTiles = TairiHotkey(
        key: .character("k"),
        modifiers: [.command]
    )
    static let newTile = TairiHotkey(
        key: .character("n"),
        modifiers: [.command]
    )
    static let newGitTile = TairiHotkey(
        key: .character("g"),
        modifiers: [.command]
    )
    static let splitHorizontally = TairiHotkey(
        key: .character("d"),
        modifiers: [.command, .shift]
    )
    static let previousTile = TairiHotkey(
        key: .leftArrow,
        modifiers: [.command, .option]
    )
    static let nextTile = TairiHotkey(
        key: .rightArrow,
        modifiers: [.command, .option]
    )
    static let moveTileLeft = TairiHotkey(
        key: .leftArrow,
        modifiers: tileReorderModifiers
    )
    static let moveTileRight = TairiHotkey(
        key: .rightArrow,
        modifiers: tileReorderModifiers
    )
    static let moveTileDown = TairiHotkey(
        key: .downArrow,
        modifiers: tileReorderModifiers
    )
    static let previousWorkspace = TairiHotkey(
        key: .upArrow,
        modifiers: [.command, .option]
    )
    static let nextWorkspace = TairiHotkey(
        key: .downArrow,
        modifiers: [.command, .option]
    )
    static let toggleSidebar = TairiHotkey(
        key: .character("b"),
        modifiers: [.command]
    )
    static let openKeyboardShortcuts = TairiHotkey(
        key: .character("/"),
        modifiers: [.command]
    )
    static let zoomOutOverview = TairiHotkey(
        key: .character("-"),
        modifiers: [.command, .option]
    )
    static let zoomInSelection = TairiHotkey(
        key: .character("="),
        modifiers: [.command, .option]
    )
    static let toggleFullscreen = TairiHotkey(
        key: .character("f"),
        modifiers: [.command, .control]
    )

    static let sections: [TairiHotkeySection] = [
        TairiHotkeySection(
            id: "search",
            title: "Search",
            entries: [
                .init(id: "searchTiles", title: "Search Tiles", hotkey: searchTiles)
            ]
        ),
        TairiHotkeySection(
            id: "tiles",
            title: "Tiles",
            entries: [
                .init(id: "newTile", title: "New Tile", hotkey: newTile),
                .init(id: "newGitTile", title: "New Git Tile", hotkey: newGitTile),
                .init(id: "splitHorizontally", title: "Split Horizontally", hotkey: splitHorizontally),
                .init(id: "previousTile", title: "Previous Tile", hotkey: previousTile),
                .init(id: "nextTile", title: "Next Tile", hotkey: nextTile),
                .init(id: "moveTileLeft", title: "Move Tile Left", hotkey: moveTileLeft),
                .init(id: "moveTileRight", title: "Move Tile Right", hotkey: moveTileRight),
                .init(id: "moveTileDown", title: "Move Tile Down", hotkey: moveTileDown),
            ]
        ),
        TairiHotkeySection(
            id: "workspaces",
            title: "Workspaces",
            entries: [
                .init(id: "previousWorkspace", title: "Previous Workspace", hotkey: previousWorkspace),
                .init(id: "nextWorkspace", title: "Next Workspace", hotkey: nextWorkspace),
                .init(id: "toggleSidebar", title: "Toggle Sidebar", hotkey: toggleSidebar),
            ]
        ),
        TairiHotkeySection(
            id: "view",
            title: "View",
            entries: [
                .init(id: "toggleFullscreen", title: "Toggle Full Screen", hotkey: toggleFullscreen),
                .init(id: "zoomOutOverview", title: "Zoom Out Overview", hotkey: zoomOutOverview),
                .init(id: "zoomInSelection", title: "Zoom In Selection", hotkey: zoomInSelection),
            ]
        ),
        TairiHotkeySection(
            id: "settings",
            title: "Settings",
            entries: [
                .init(id: "openAppSettings", title: "App Settings", hotkey: openAppSettings),
                .init(id: "openGhosttySettings", title: "Ghostty Settings", hotkey: openGhosttySettings),
                .init(
                    id: "reloadGhosttyConfiguration",
                    title: "Reload Ghostty Configuration",
                    hotkey: reloadGhosttyConfiguration
                ),
            ]
        ),
    ]

    static func tileReorderDirection(for event: NSEvent) -> TileReorderDirection? {
        if moveTileLeft.matches(event) {
            return .left
        }
        if moveTileRight.matches(event) {
            return .right
        }
        if moveTileDown.matches(event) {
            return .down
        }
        return nil
    }

}

extension View {
    func tairiKeyboardShortcut(_ hotkey: TairiHotkey) -> some View {
        keyboardShortcut(hotkey.keyEquivalent, modifiers: hotkey.modifiers)
    }
}

extension EventModifiers {
    fileprivate var nsEventModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.control) { flags.insert(.control) }
        if contains(.option) { flags.insert(.option) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.command) { flags.insert(.command) }
        return flags
    }

    fileprivate var displayPrefix: String {
        var prefix = ""
        if contains(.control) { prefix += "⌃" }
        if contains(.option) { prefix += "⌥" }
        if contains(.shift) { prefix += "⇧" }
        if contains(.command) { prefix += "⌘" }
        return prefix
    }

    fileprivate var displayTokens: [String] {
        var tokens: [String] = []
        if contains(.control) { tokens.append("⌃") }
        if contains(.option) { tokens.append("⌥") }
        if contains(.shift) { tokens.append("⇧") }
        if contains(.command) { tokens.append("⌘") }
        return tokens
    }
}

extension NSEvent.ModifierFlags {
    fileprivate static let tairiShortcutRelevant: Self = [.command, .option, .control, .shift]
}

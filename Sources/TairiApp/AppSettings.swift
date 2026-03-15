import Combine
import Foundation
import CoreGraphics

enum TerminalExitBehavior: String, CaseIterable, Identifiable {
    case closeImmediately
    case waitForKeyPress

    var id: Self { self }

    var title: String {
        switch self {
        case .waitForKeyPress:
            "Wait for next key press"
        case .closeImmediately:
            "Close tile immediately"
        }
    }

    var detail: String {
        switch self {
        case .waitForKeyPress:
            "Keeps the terminal visible after the shell exits until you press a key."
        case .closeImmediately:
            "Closes the tile as soon as the shell or command exits."
        }
    }

    var waitAfterCommandEnabled: Bool {
        self == .waitForKeyPress
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let terminalExitBehaviorKey = "terminalExitBehavior"
    static let windowGlassOpacityPercentKey = "windowGlassOpacityPercent"
    static let legacyWindowOpacityPercentKey = "windowOpacityPercent"
    static let legacyTileBackgroundOpacityPercentKey = "tileBackgroundOpacityPercent"
    static let sidebarHiddenKey = "sidebarHidden"
    static let defaultTerminalExitBehavior: TerminalExitBehavior = .closeImmediately
    static let defaultWindowGlassOpacityPercent: Double = 100
    static let defaultSidebarHidden = false

    @Published var terminalExitBehavior: TerminalExitBehavior {
        didSet {
            guard terminalExitBehavior != oldValue else { return }
            userDefaults.set(terminalExitBehavior.rawValue, forKey: Self.terminalExitBehaviorKey)
            TairiLog.write("settings terminalExitBehavior=\(terminalExitBehavior.rawValue)")
        }
    }

    @Published var windowGlassOpacityPercent: Double {
        didSet {
            let clampedValue = Self.clampedWindowGlassOpacityPercent(windowGlassOpacityPercent)
            if clampedValue != windowGlassOpacityPercent {
                windowGlassOpacityPercent = clampedValue
                return
            }
            guard clampedValue != oldValue else { return }
            userDefaults.set(clampedValue, forKey: Self.windowGlassOpacityPercentKey)
            TairiLog.write("settings windowGlassOpacityPercent=\(Int(clampedValue.rounded()))")
        }
    }

    var windowGlassOpacity: CGFloat {
        CGFloat(windowGlassOpacityPercent / 100)
    }

    @Published var sidebarHidden: Bool {
        didSet {
            guard sidebarHidden != oldValue else { return }
            userDefaults.set(sidebarHidden, forKey: Self.sidebarHiddenKey)
            TairiLog.write("settings sidebarHidden=\(sidebarHidden)")
        }
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if let rawValue = userDefaults.string(forKey: Self.terminalExitBehaviorKey),
           let behavior = TerminalExitBehavior(rawValue: rawValue) {
            terminalExitBehavior = behavior
        } else {
            terminalExitBehavior = Self.defaultTerminalExitBehavior
        }

        let storedOpacity =
            (userDefaults.object(forKey: Self.windowGlassOpacityPercentKey) as? Double)
            ?? (userDefaults.object(forKey: Self.legacyWindowOpacityPercentKey) as? Double)
            ?? (userDefaults.object(forKey: Self.legacyTileBackgroundOpacityPercentKey) as? Double)
        windowGlassOpacityPercent = Self.clampedWindowGlassOpacityPercent(
            storedOpacity ?? Self.defaultWindowGlassOpacityPercent
        )

        if userDefaults.object(forKey: Self.sidebarHiddenKey) != nil {
            sidebarHidden = userDefaults.bool(forKey: Self.sidebarHiddenKey)
        } else {
            sidebarHidden = Self.defaultSidebarHidden
        }
    }

    private static func clampedWindowGlassOpacityPercent(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }
}

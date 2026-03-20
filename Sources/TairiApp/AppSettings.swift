import Combine
@preconcurrency import AppKit
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
    static let animationsEnabledKey = "animationsEnabled"
    static let animationSpeedMultiplierKey = "animationSpeedMultiplier"
    static let defaultTerminalExitBehavior: TerminalExitBehavior = .closeImmediately
    static let defaultWindowGlassOpacityPercent: Double = 0
    static let defaultSidebarHidden = false
    static let defaultAnimationsEnabled = true
    static let defaultAnimationSpeedMultiplier: Double = 1

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

    @Published var animationsEnabled: Bool {
        didSet {
            guard animationsEnabled != oldValue else { return }
            userDefaults.set(animationsEnabled, forKey: Self.animationsEnabledKey)
            TairiLog.write("settings animationsEnabled=\(animationsEnabled)")
        }
    }

    @Published var animationSpeedMultiplier: Double {
        didSet {
            let clampedValue = Self.clampedAnimationSpeedMultiplier(animationSpeedMultiplier)
            if clampedValue != animationSpeedMultiplier {
                animationSpeedMultiplier = clampedValue
                return
            }
            guard clampedValue != oldValue else { return }
            userDefaults.set(clampedValue, forKey: Self.animationSpeedMultiplierKey)
            TairiLog.write("settings animationSpeedMultiplier=\(clampedValue)")
        }
    }

    @Published private(set) var systemReduceMotionEnabled: Bool

    var animationPolicy: AppAnimationPolicy {
        AppAnimationPolicy(
            animationsEnabled: animationsEnabled,
            speedMultiplier: animationSpeedMultiplier,
            systemReduceMotionEnabled: systemReduceMotionEnabled,
            uiTesting: uiTestingProvider()
        )
    }

    private let userDefaults: UserDefaults
    private let reduceMotionProvider: () -> Bool
    private let uiTestingProvider: () -> Bool
    private let notificationCenter: NotificationCenter
    private var accessibilityObserver: NSObjectProtocol?

    init(
        userDefaults: UserDefaults = .standard,
        reduceMotionProvider: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
        uiTestingProvider: @escaping () -> Bool = { TairiEnvironment.isUITesting },
        notificationCenter: NotificationCenter = .default
    ) {
        self.userDefaults = userDefaults
        self.reduceMotionProvider = reduceMotionProvider
        self.uiTestingProvider = uiTestingProvider
        self.notificationCenter = notificationCenter
        systemReduceMotionEnabled = reduceMotionProvider()

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

        if userDefaults.object(forKey: Self.animationsEnabledKey) != nil {
            animationsEnabled = userDefaults.bool(forKey: Self.animationsEnabledKey)
        } else {
            animationsEnabled = Self.defaultAnimationsEnabled
        }

        let storedAnimationSpeedMultiplier =
            (userDefaults.object(forKey: Self.animationSpeedMultiplierKey) as? Double)
            ?? Self.defaultAnimationSpeedMultiplier
        animationSpeedMultiplier = Self.clampedAnimationSpeedMultiplier(storedAnimationSpeedMultiplier)

        accessibilityObserver = notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSystemReduceMotionEnabled()
            }
        }
    }

    deinit {
        if let accessibilityObserver {
            notificationCenter.removeObserver(accessibilityObserver)
        }
    }

    private static func clampedWindowGlassOpacityPercent(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }

    private static func clampedAnimationSpeedMultiplier(_ value: Double) -> Double {
        min(max(value, 0.5), 2)
    }

    private func refreshSystemReduceMotionEnabled() {
        let nextValue = reduceMotionProvider()
        guard nextValue != systemReduceMotionEnabled else { return }
        systemReduceMotionEnabled = nextValue
        TairiLog.write("settings systemReduceMotionEnabled=\(nextValue)")
    }
}

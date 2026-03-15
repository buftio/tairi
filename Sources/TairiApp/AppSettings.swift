import Combine
import Foundation

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
    static let defaultTerminalExitBehavior: TerminalExitBehavior = .closeImmediately

    @Published var terminalExitBehavior: TerminalExitBehavior {
        didSet {
            guard terminalExitBehavior != oldValue else { return }
            userDefaults.set(terminalExitBehavior.rawValue, forKey: Self.terminalExitBehaviorKey)
            TairiLog.write("settings terminalExitBehavior=\(terminalExitBehavior.rawValue)")
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
    }
}

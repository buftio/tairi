import Foundation

struct GhosttyTileLifecycle {
    struct CommandFinish {
        let exitCode: Int
        let recordedAt: Date
    }

    var title: String
    var pwd: String?
    var lastCommandFinish: CommandFinish?

    init(title: String = "shell", pwd: String? = nil, lastCommandFinish: CommandFinish? = nil) {
        self.title = title
        self.pwd = pwd
        self.lastCommandFinish = lastCommandFinish
    }

    func summary(referenceDate: Date = Date()) -> String {
        let pwdSummary = pwd?.isEmpty == false ? pwd! : "none"
        let commandSummary: String
        if let lastCommandFinish {
            let age = referenceDate.timeIntervalSince(lastCommandFinish.recordedAt)
            commandSummary = "exitCode=\(lastCommandFinish.exitCode) age=\(String(format: "%.3f", age))"
        } else {
            commandSummary = "none"
        }

        return "title=\(title.debugDescription) pwd=\(pwdSummary.debugDescription) lastCommandFinished=\(commandSummary)"
    }
}

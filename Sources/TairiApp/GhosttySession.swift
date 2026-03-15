import Foundation
import GhosttyDyn

@MainActor
final class GhosttyAppContext {
    weak var runtime: GhosttyRuntime?
    let sessionID: UUID
    var app: ghostty_app_t?
    var wakeupCount = 0

    init(runtime: GhosttyRuntime, sessionID: UUID) {
        self.runtime = runtime
        self.sessionID = sessionID
    }
}

@MainActor
final class GhosttySession {
    let id: UUID
    let appContext: GhosttyAppContext
    let surfaceView: GhosttySurfaceView
    var lifecycle: GhosttyTileLifecycle
    var state: GhosttySessionState
    var attachedTileID: UUID?

    init(
        id: UUID,
        appContext: GhosttyAppContext,
        surfaceView: GhosttySurfaceView,
        title: String = "shell",
        pwd: String? = nil
    ) {
        self.id = id
        self.appContext = appContext
        self.surfaceView = surfaceView
        lifecycle = GhosttyTileLifecycle(title: title, pwd: pwd)
        state = .running
    }

    var title: String {
        lifecycle.title
    }

    var pwd: String? {
        lifecycle.pwd
    }

    func updateTitle(_ title: String) {
        lifecycle.title = title.isEmpty ? "shell" : title
    }

    func updatePWD(_ pwd: String) {
        lifecycle.pwd = pwd
    }

    func recordCommandFinish(exitCode: Int, recordedAt: Date = Date()) {
        lifecycle.lastCommandFinish = GhosttyTileLifecycle.CommandFinish(
            exitCode: exitCode,
            recordedAt: recordedAt
        )
    }
}

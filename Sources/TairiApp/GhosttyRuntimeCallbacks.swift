import AppKit
import Foundation
import GhosttyDyn

@MainActor
extension GhosttyRuntime {
    func handleCloseSurface(for sessionID: UUID, processAlive: Bool) {
        guard let session = sessionRegistry.session(id: sessionID) else { return }
        let processExited = session.surfaceView.surface.map(tairi_ghostty_surface_process_exited) ?? false
        TairiLog.write(
            "ghostty close_surface session=\(sessionID.uuidString) tile=\(session.attachedTileID?.uuidString ?? "detached") processAlive=\(processAlive) processExited=\(processExited) \(lifecycleSummary(for: sessionID))"
        )

        guard processExited else {
            TairiLog.write("ghostty close_surface ignored for session=\(sessionID.uuidString)")
            return
        }

        guard let tileID = session.attachedTileID else {
            destroyDetachedExitedSession(sessionID: sessionID, source: "close_surface")
            return
        }

        guard shouldAcceptExit(for: tileID, reason: "close_surface") else {
            return
        }

        terminateSession(for: tileID, reason: .exitBehaviorAutoClose)
        store.closeTile(tileID)
    }

    static let wakeup: ghostty_runtime_wakeup_cb = { userdata in
        guard let userdata else { return }
        let opaque = UInt(bitPattern: userdata)
        DispatchQueue.main.async {
            guard let rawPointer = UnsafeMutableRawPointer(bitPattern: opaque) else { return }
            let context = Unmanaged<GhosttyAppContext>.fromOpaque(rawPointer).takeUnretainedValue()
            context.wakeupCount += 1
            if context.wakeupCount <= 5 || context.wakeupCount == 10 || context.wakeupCount.isMultiple(of: 100) {
                TairiLog.write(
                    "ghostty wakeup session=\(context.sessionID.uuidString) count=\(context.wakeupCount) context=\(TairiLog.pointer(rawPointer)) app=\(GhosttyRuntime.describeHandle(context.app))"
                )
            }
            if let app = context.app {
                tairi_ghostty_app_tick(app)
            } else if context.wakeupCount <= 5 {
                TairiLog.write(
                    "ghostty wakeup dropped session=\(context.sessionID.uuidString) count=\(context.wakeupCount) context=\(TairiLog.pointer(rawPointer)) app=nil"
                )
            }
        }
    }

    static let action: ghostty_runtime_action_cb = { app, target, action in
        guard let userdata = tairi_ghostty_app_userdata(app) else {
            TairiLog.write("ghostty action dropped app=\(GhosttyRuntime.describeHandle(app)) reason=missing_userdata tag=\(action.tag.rawValue)")
            return false
        }
        let context = Unmanaged<GhosttyAppContext>.fromOpaque(userdata).takeUnretainedValue()
        guard let runtime = context.runtime else {
            TairiLog.write(
                "ghostty action dropped session=\(context.sessionID.uuidString) context=\(TairiLog.pointer(userdata)) app=\(GhosttyRuntime.describeHandle(app)) reason=runtime_nil tag=\(action.tag.rawValue)"
            )
            return false
        }
        return runtime.handle(action: action, target: target, sourceSessionID: context.sessionID)
    }

    static let readClipboard: ghostty_runtime_read_clipboard_cb = { userdata, location, state in
        guard let userdata else {
            TairiLog.write("ghostty readClipboard dropped reason=missing_userdata")
            return false
        }
        let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
        guard let surface = view.surface else {
            TairiLog.write("ghostty readClipboard dropped session=\(view.sessionID.uuidString) reason=surface_nil")
            return false
        }
        guard let pasteboard = TerminalPasteboard.pasteboard(for: location) else {
            TairiLog.write(
                "ghostty readClipboard dropped session=\(view.sessionID.uuidString) reason=unsupported_pasteboard location=\(location.rawValue)"
            )
            return false
        }
        guard let value = TerminalPasteboard.preferredPasteString(from: pasteboard) else {
            TairiLog.write("ghostty readClipboard empty session=\(view.sessionID.uuidString)")
            return false
        }
        value.withCString { ptr in
            tairi_ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
        }
        return true
    }

    static let confirmReadClipboard: ghostty_runtime_confirm_read_clipboard_cb = { userdata, value, state, _ in
        guard let userdata, let value else { return }
        let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
        guard let surface = view.surface else {
            TairiLog.write("ghostty confirmReadClipboard dropped session=\(view.sessionID.uuidString) reason=surface_nil")
            return
        }
        tairi_ghostty_surface_complete_clipboard_request(surface, value, state, true)
    }

    static let writeClipboard: ghostty_runtime_write_clipboard_cb = { _, _, content, len, _ in
        guard let content, len > 0 else { return }
        let items = UnsafeBufferPointer(start: content, count: len)
        guard let first = items.first(where: { item in
            guard let mime = item.mime else { return false }
            return String(cString: mime) == "text/plain"
        }), let data = first.data else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(cString: data), forType: .string)
    }

    static let closeSurface: ghostty_runtime_close_surface_cb = { userdata, processAlive in
        guard let userdata else { return }
        let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
        view.runtime.handleCloseSurface(for: view.sessionID, processAlive: processAlive)
    }

    static func describeHandle(_ handle: UnsafeMutableRawPointer?) -> String {
        TairiLog.pointer(handle)
    }

    func describe(state: GhosttySessionState) -> String {
        switch state {
        case .running:
            "running"
        case .exited(let exitCode):
            "exited(\(exitCode))"
        }
    }
}

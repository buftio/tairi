import AppKit
import Foundation
import GhosttyDyn

@MainActor
final class GhosttyRuntime: ObservableObject {
    private final class WeakSurface {
        weak var value: GhosttySurfaceView?
        init(_ value: GhosttySurfaceView?) { self.value = value }
    }

    @Published private(set) var errorMessage: String?
    private(set) var app: ghostty_app_t?

    private let store: WorkspaceStore
    private var surfaces: [UUID: WeakSurface] = [:]

    init(store: WorkspaceStore) {
        self.store = store
        bootstrap()
    }

    func register(surfaceView: GhosttySurfaceView, sessionID: UUID) {
        surfaces[sessionID] = WeakSurface(surfaceView)
    }

    func unregister(sessionID: UUID) {
        surfaces.removeValue(forKey: sessionID)
    }

    func focus(sessionID: UUID) {
        store.selectSession(sessionID)
        surfaces[sessionID]?.value?.focusSurface()
    }

    private func bootstrap() {
        configureBundledGhosttyPaths()
        TairiLog.write("bootstrap start")
        TairiLog.write("GHOSTTY_RESOURCES_DIR=\(ProcessInfo.processInfo.environment["GHOSTTY_RESOURCES_DIR"] ?? "unset")")
        TairiLog.write("TAIRI_BUNDLED_GHOSTTY_BIN=\(ProcessInfo.processInfo.environment["TAIRI_BUNDLED_GHOSTTY_BIN"] ?? "unset")")

        if let error = tairi_ghostty_load(nil) {
            errorMessage = String(cString: error)
            TairiLog.write("ghostty load failed: \(errorMessage ?? "unknown")")
            return
        }

        if tairi_ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != GHOSTTY_SUCCESS {
            errorMessage = "ghostty_init failed"
            TairiLog.write(errorMessage ?? "ghostty_init failed")
            return
        }

        guard let config = tairi_ghostty_config_new() else {
            errorMessage = "ghostty_config_new failed"
            TairiLog.write(errorMessage ?? "ghostty_config_new failed")
            return
        }
        defer { tairi_ghostty_config_free(config) }

        tairi_ghostty_config_load_default_files(config)
        tairi_ghostty_config_load_recursive_files(config)
        tairi_ghostty_config_finalize(config)

        var runtimeConfig = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: true,
            wakeup_cb: Self.wakeup,
            action_cb: Self.action,
            read_clipboard_cb: Self.readClipboard,
            confirm_read_clipboard_cb: Self.confirmReadClipboard,
            write_clipboard_cb: Self.writeClipboard,
            close_surface_cb: Self.closeSurface
        )

        guard let app = tairi_ghostty_app_new(&runtimeConfig, config) else {
            errorMessage = "ghostty_app_new failed"
            TairiLog.write(errorMessage ?? "ghostty_app_new failed")
            return
        }

        self.app = app
        TairiLog.write("ghostty app created")
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let app = self.app else { return }
                tairi_ghostty_app_set_focus(app, true)
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let app = self.app else { return }
                tairi_ghostty_app_set_focus(app, false)
            }
        }
    }

    private func configureBundledGhosttyPaths() {
        let resourcesURL = Bundle.main.resourceURL
        let bundledResources = resourcesURL?.appendingPathComponent("ghostty")
        let bundledBinary = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Frameworks/GhosttyRuntime.app/Contents/MacOS/ghostty")
        let vendoredRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Vendor/Ghostty")
        let vendoredVersion = (try? FileManager.default.contentsOfDirectory(
            at: vendoredRoot,
            includingPropertiesForKeys: nil
        ))?
        .filter(\.hasDirectoryPath)
        .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        .last
        let vendoredResources = vendoredVersion?
            .appendingPathComponent("GhosttyRuntime.app/Contents/Resources/ghostty")
        let vendoredBinary = vendoredVersion?
            .appendingPathComponent("GhosttyRuntime.app/Contents/MacOS/ghostty")

        if let bundledResources, FileManager.default.fileExists(atPath: bundledResources.path(percentEncoded: false)) {
            setenv("GHOSTTY_RESOURCES_DIR", bundledResources.path(percentEncoded: false), 1)
        } else if let vendoredResources, FileManager.default.fileExists(atPath: vendoredResources.path(percentEncoded: false)) {
            setenv("GHOSTTY_RESOURCES_DIR", vendoredResources.path(percentEncoded: false), 1)
        }

        if FileManager.default.fileExists(atPath: bundledBinary.path(percentEncoded: false)) {
            setenv("TAIRI_BUNDLED_GHOSTTY_BIN", bundledBinary.path(percentEncoded: false), 1)
        } else if let vendoredBinary, FileManager.default.fileExists(atPath: vendoredBinary.path(percentEncoded: false)) {
            setenv("TAIRI_BUNDLED_GHOSTTY_BIN", vendoredBinary.path(percentEncoded: false), 1)
        }
    }

    private func sessionID(for target: ghostty_target_s) -> UUID? {
        guard target.tag == GHOSTTY_TARGET_SURFACE else { return nil }
        guard let userdata = tairi_ghostty_surface_userdata(target.target.surface) else { return nil }
        let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
        return view.sessionID
    }

    private func handle(action: ghostty_action_s, target: ghostty_target_s) -> Bool {
        guard let sessionID = sessionID(for: target) else {
            return false
        }

        switch action.tag {
        case GHOSTTY_ACTION_NEW_WINDOW, GHOSTTY_ACTION_NEW_TAB, GHOSTTY_ACTION_NEW_SPLIT:
            store.selectSession(sessionID)
            _ = store.addSession(nextTo: sessionID)
            return true

        case GHOSTTY_ACTION_GOTO_SPLIT:
            switch action.action.goto_split {
            case GHOSTTY_GOTO_SPLIT_PREVIOUS, GHOSTTY_GOTO_SPLIT_LEFT:
                store.selectAdjacentSession(offset: -1)
            default:
                store.selectAdjacentSession(offset: 1)
            }
            if let selected = store.selectedSessionID {
                focus(sessionID: selected)
            }
            return true

        case GHOSTTY_ACTION_SET_TITLE:
            if let title = action.action.set_title.title {
                store.updateTitle(String(cString: title), for: sessionID)
            }
            return true

        case GHOSTTY_ACTION_PWD:
            if let pwd = action.action.pwd.pwd {
                store.updatePWD(String(cString: pwd), for: sessionID)
            }
            return true

        case GHOSTTY_ACTION_OPEN_URL:
            guard let value = action.action.open_url.url else { return false }
            let string = String(cString: value)
            guard let url = URL(string: string) else { return false }
            NSWorkspace.shared.open(url)
            return true

        case GHOSTTY_ACTION_CLOSE_WINDOW, GHOSTTY_ACTION_CLOSE_TAB:
            if target.tag == GHOSTTY_TARGET_SURFACE {
                store.closeSession(sessionID)
                return true
            }
            // Our UI manages a single app window with many independent
            // terminal columns, so app-level Ghostty close requests should
            // not tear down every surface just because one shell exited.
            return true

        case GHOSTTY_ACTION_CLOSE_ALL_WINDOWS, GHOSTTY_ACTION_QUIT:
            // Swallow Ghostty-level app shutdown actions. The host app owns
            // lifecycle; terminals exiting should only affect their column.
            return true

        default:
            return false
        }
    }

    private static func instance(from pointer: UnsafeMutableRawPointer?) -> GhosttyRuntime {
        Unmanaged<GhosttyRuntime>.fromOpaque(pointer!).takeUnretainedValue()
    }

    private static let wakeup: ghostty_runtime_wakeup_cb = { userdata in
        let runtime = instance(from: userdata)
        DispatchQueue.main.async {
            if let app = runtime.app {
                tairi_ghostty_app_tick(app)
            }
        }
    }

    private static let action: ghostty_runtime_action_cb = { app, target, action in
        guard let userdata = tairi_ghostty_app_userdata(app) else { return false }
        let runtime = instance(from: userdata)
        return runtime.handle(action: action, target: target)
    }

    private static let readClipboard: ghostty_runtime_read_clipboard_cb = { userdata, _, state in
        guard let userdata else { return false }
        let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
        guard let surface = view.surface else { return false }
        guard let value = NSPasteboard.general.string(forType: .string) else { return false }
        value.withCString { ptr in
            tairi_ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
        }
        return true
    }

    private static let confirmReadClipboard: ghostty_runtime_confirm_read_clipboard_cb = { userdata, value, state, _ in
        guard let userdata, let value else { return }
        let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
        guard let surface = view.surface else { return }
        tairi_ghostty_surface_complete_clipboard_request(surface, value, state, true)
    }

    private static let writeClipboard: ghostty_runtime_write_clipboard_cb = { _, _, content, len, _ in
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

    private static let closeSurface: ghostty_runtime_close_surface_cb = { userdata, _ in
        guard let userdata else { return }
        let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
        view.runtime.store.closeSession(view.sessionID)
    }
}

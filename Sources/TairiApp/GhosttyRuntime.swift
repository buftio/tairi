import AppKit
import Combine
import Foundation
import GhosttyDyn

@MainActor
final class GhosttyRuntime: ObservableObject {
    private final class AppContext {
        weak var runtime: GhosttyRuntime?
        let tileID: UUID
        var app: ghostty_app_t?

        init(runtime: GhosttyRuntime, tileID: UUID) {
            self.runtime = runtime
            self.tileID = tileID
        }
    }

    @Published private(set) var errorMessage: String?

    fileprivate let store: WorkspaceStore
    private let interactionController: WorkspaceInteractionController
    private var surfaces: [UUID: GhosttySurfaceView] = [:]
    private var appContexts: [UUID: AppContext] = [:]
    private let actionAdapter = GhosttyActionAdapter()
    private var storeObserver: AnyCancellable?
    private var didInstallAppObservers = false
    private var lastInputTileID: UUID?
    private var lastInputAt: Date?

    init(store: WorkspaceStore, interactionController: WorkspaceInteractionController) {
        self.store = store
        self.interactionController = interactionController
        observeStore()
        bootstrap()
    }

    func app(for tileID: UUID) -> ghostty_app_t? {
        if let app = appContexts[tileID]?.app {
            return app
        }
        return createApp(for: tileID)
    }

    func attachSurface(tileID: UUID, to containerView: NSView) {
        let surfaceView = surfaceView(for: tileID)
        if surfaceView.superview !== containerView {
            surfaceView.removeFromSuperview()
            containerView.addSubview(surfaceView)
        }
        surfaceView.frame = containerView.bounds
        surfaceView.autoresizingMask = [.width, .height]
    }

    func detachSurface(tileID: UUID) {
        surfaces[tileID]?.removeFromSuperview()
    }

    func focus(tileID: UUID, transition: WorkspaceInteractionController.TileTransition = .immediate) {
        interactionController.selectTile(tileID, transition: transition)
        focusSurface(tileID: tileID)
    }

    func focusSurface(tileID: UUID) {
        surfaces[tileID]?.focusSurface()
    }

    func recordInput(for tileID: UUID) {
        lastInputTileID = tileID
        lastInputAt = Date()
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

        switch GhosttyRuntimeCompatibility.validateLoadedRuntime() {
        case .success(let metadata):
            TairiLog.write(
                "ghostty runtime version=\(metadata.version) build_mode=\(metadata.buildMode.rawValue) header=\(GhosttyRuntimeCompatibility.headerSignature)"
            )
        case .failure(let error):
            errorMessage = error.message
            TairiLog.write(error.message)
            return
        }

        if tairi_ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != GHOSTTY_SUCCESS {
            errorMessage = "ghostty_init failed"
            TairiLog.write(errorMessage ?? "ghostty_init failed")
            return
        }

        installAppObserversIfNeeded()
    }

    private func installAppObserversIfNeeded() {
        guard !didInstallAppObservers else { return }
        didInstallAppObservers = true

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setAllAppsFocused(true)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setAllAppsFocused(false)
            }
        }
    }

    private func setAllAppsFocused(_ focused: Bool) {
        for context in appContexts.values {
            if let app = context.app {
                tairi_ghostty_app_set_focus(app, focused)
            }
        }
    }

    private func createApp(for tileID: UUID) -> ghostty_app_t? {
        guard errorMessage == nil else { return nil }

        guard let config = tairi_ghostty_config_new() else {
            errorMessage = "ghostty_config_new failed"
            TairiLog.write(errorMessage ?? "ghostty_config_new failed")
            return nil
        }
        defer { tairi_ghostty_config_free(config) }

        tairi_ghostty_config_load_default_files(config)
        tairi_ghostty_config_load_recursive_files(config)
        tairi_ghostty_config_finalize(config)

        let context = AppContext(runtime: self, tileID: tileID)
        let retainedContext = Unmanaged.passRetained(context)
        var runtimeConfig = ghostty_runtime_config_s(
            userdata: retainedContext.toOpaque(),
            supports_selection_clipboard: true,
            wakeup_cb: Self.wakeup,
            action_cb: Self.action,
            read_clipboard_cb: Self.readClipboard,
            confirm_read_clipboard_cb: Self.confirmReadClipboard,
            write_clipboard_cb: Self.writeClipboard,
            close_surface_cb: Self.closeSurface
        )

        guard let app = tairi_ghostty_app_new(&runtimeConfig, config) else {
            retainedContext.release()
            errorMessage = "ghostty_app_new failed"
            TairiLog.write(errorMessage ?? "ghostty_app_new failed")
            return nil
        }

        context.app = app
        appContexts[tileID] = context
        TairiLog.write("ghostty app created tile=\(tileID.uuidString)")
        return app
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

    private func observeStore() {
        storeObserver = store.$workspaces
            .map { workspaces in
                Set(workspaces.flatMap(\.tiles).map(\.id))
            }
            .sink { [weak self] liveTileIDs in
                guard let self else { return }
                let retiredTileIDs = Set(self.surfaces.keys).subtracting(liveTileIDs)
                for tileID in retiredTileIDs {
                    self.disposeSurface(tileID: tileID)
                }
            }
    }

    private func surfaceView(for tileID: UUID) -> GhosttySurfaceView {
        if let surfaceView = surfaces[tileID] {
            return surfaceView
        }

        let surfaceView = GhosttySurfaceView(runtime: self, tileID: tileID)
        surfaces[tileID] = surfaceView
        return surfaceView
    }

    private func disposeSurface(tileID: UUID) {
        guard let surfaceView = surfaces.removeValue(forKey: tileID) else { return }
        surfaceView.dispose()

        guard let context = appContexts.removeValue(forKey: tileID) else { return }
        if let app = context.app {
            tairi_ghostty_app_free(app)
        }
        Unmanaged.passUnretained(context).release()
    }

    private func logAction(_ tag: ghostty_action_tag_e, tileID: UUID?, target: ghostty_target_s) {
        let targetLabel = target.tag == GHOSTTY_TARGET_SURFACE ? "surface" : "app"
        let tileLabel = tileID?.uuidString ?? "none"
        TairiLog.write("ghostty action \(GhosttyActionAdapter.actionName(tag)) target=\(targetLabel) tile=\(tileLabel)")
    }

    private func shouldAcceptExit(for tileID: UUID, reason: String) -> Bool {
        guard lastInputTileID == tileID, let lastInputAt else {
            TairiLog.write("ghostty ignored \(reason) for tile=\(tileID.uuidString) owner=\(lastInputTileID?.uuidString ?? "none")")
            return false
        }

        let age = Date().timeIntervalSince(lastInputAt)
        guard age <= 2 else {
            TairiLog.write("ghostty ignored \(reason) for tile=\(tileID.uuidString) input_age=\(String(format: "%.3f", age))")
            return false
        }

        TairiLog.write("ghostty accepted \(reason) for tile=\(tileID.uuidString) input_age=\(String(format: "%.3f", age))")
        return true
    }

    private func tileID(for target: ghostty_target_s) -> UUID? {
        guard target.tag == GHOSTTY_TARGET_SURFACE else { return nil }
        guard let userdata = tairi_ghostty_surface_userdata(target.target.surface) else { return nil }
        let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
        return view.tileID
    }

    private func handle(action: ghostty_action_s, target: ghostty_target_s) -> Bool {
        let tileID = tileID(for: target)
        logAction(action.tag, tileID: tileID, target: target)
        let event = actionAdapter.decode(action: action, tileID: tileID)
        return handle(event: event)
    }

    private func handle(event: GhosttyRuntimeEvent) -> Bool {
        switch event {
        case .createTile(let tileID):
            interactionController.selectTile(tileID)
            _ = interactionController.addTerminalTile(nextTo: tileID, transition: .preserveViewport)
            return true

        case .selectAdjacentTile(let offset):
            interactionController.selectAdjacentTile(offset: offset)
            if let selectedTileID = store.selectedTileID {
                focusSurface(tileID: selectedTileID)
            }
            return true

        case .updateTitle(let tileID, let title):
            store.updateTitle(title, for: tileID)
            return true

        case .updatePWD(let tileID, let pwd):
            store.updatePWD(pwd, for: tileID)
            return true

        case .openURL(let url):
            NSWorkspace.shared.open(url)
            return true

        case .childExited(let tileID, let exitCode, let reason):
            TairiLog.write("ghostty child exited tile=\(tileID.uuidString) exitCode=\(exitCode) reason=\(reason.rawValue)")
            guard shouldAcceptExit(for: tileID, reason: reason.rawValue) else {
                return true
            }
            store.closeTile(tileID)
            return true

        case .commandFinished(let tileID, let exitCode):
            TairiLog.write("ghostty command finished tile=\(tileID.uuidString) exitCode=\(exitCode)")
            return true

        case .ignore:
            return true

        case .unhandled:
            return false
        }
    }

    private static let wakeup: ghostty_runtime_wakeup_cb = { userdata in
        guard let userdata else { return }
        let opaque = UInt(bitPattern: userdata)
        DispatchQueue.main.async {
            guard let rawPointer = UnsafeMutableRawPointer(bitPattern: opaque) else { return }
            let context = Unmanaged<AppContext>.fromOpaque(rawPointer).takeUnretainedValue()
            if let app = context.app {
                tairi_ghostty_app_tick(app)
            }
        }
    }

    private static let action: ghostty_runtime_action_cb = { app, target, action in
        guard let userdata = tairi_ghostty_app_userdata(app) else { return false }
        let context = Unmanaged<AppContext>.fromOpaque(userdata).takeUnretainedValue()
        guard let runtime = context.runtime else { return false }
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

    private static let closeSurface: ghostty_runtime_close_surface_cb = { userdata, processAlive in
        guard let userdata else { return }
        let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
        let processExited = view.surface.map(tairi_ghostty_surface_process_exited) ?? false
        TairiLog.write(
            "ghostty close_surface tile=\(view.tileID.uuidString) processAlive=\(processAlive) processExited=\(processExited)"
        )

        guard processExited else {
            TairiLog.write("ghostty close_surface ignored for tile=\(view.tileID.uuidString)")
            return
        }

        guard view.runtime.shouldAcceptExit(for: view.tileID, reason: "close_surface") else {
            return
        }

        view.runtime.store.closeTile(view.tileID)
    }
}

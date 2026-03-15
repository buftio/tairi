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
        var wakeupCount = 0

        init(runtime: GhosttyRuntime, tileID: UUID) {
            self.runtime = runtime
            self.tileID = tileID
        }
    }

    @Published private(set) var errorMessage: String?

    fileprivate let store: WorkspaceStore
    private let interactionController: WorkspaceInteractionController
    private let settings: AppSettings
    private var surfaces: [UUID: GhosttySurfaceView] = [:]
    private var appContexts: [UUID: AppContext] = [:]
    private let actionAdapter = GhosttyActionAdapter()
    private var storeObserver: AnyCancellable?
    private var settingsObserver: AnyCancellable?
    private var didInstallAppObservers = false
    private var lastInputTileID: UUID?
    private var lastInputAt: Date?

    init(store: WorkspaceStore, interactionController: WorkspaceInteractionController, settings: AppSettings) {
        self.store = store
        self.interactionController = interactionController
        self.settings = settings
        observeStore()
        observeSettings()
        bootstrap()
    }

    var waitAfterCommandEnabled: Bool {
        settings.terminalExitBehavior.waitAfterCommandEnabled
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

    func didFocusSurface(tileID: UUID) {
        interactionController.selectTile(tileID)
    }

    func focusSurface(tileID: UUID) {
        surfaces[tileID]?.focusSurface()
    }

    func workingDirectory(for tileID: UUID) -> String {
        store.tile(tileID)?.pwd ?? TerminalWorkingDirectory.defaultDirectoryForEmptyWorkspace()
    }

    func spawnWorkingDirectory(for tileID: UUID?) -> String {
        guard let tileID else {
            return TerminalWorkingDirectory.defaultDirectoryForEmptyWorkspace()
        }

        if let liveDirectory = inheritedWorkingDirectory(for: tileID) {
            return liveDirectory
        }

        return workingDirectory(for: tileID)
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
        return withGhosttyConfig { config in
            let context = AppContext(runtime: self, tileID: tileID)
            let retainedContext = Unmanaged.passRetained(context)
            let contextPointer = retainedContext.toOpaque()
            TairiLog.write(
                "ghostty creating app tile=\(tileID.uuidString) context=\(TairiLog.pointer(contextPointer)) selectedWorkspace=\(store.selectedWorkspaceID.uuidString) selectedTile=\(store.selectedTileID?.uuidString ?? "none")"
            )
            var runtimeConfig = ghostty_runtime_config_s(
                userdata: contextPointer,
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
            TairiLog.write(
                "ghostty app created tile=\(tileID.uuidString) context=\(TairiLog.pointer(contextPointer)) app=\(Self.describeHandle(app))"
            )
            return app
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

    private func observeSettings() {
        settingsObserver = settings.$terminalExitBehavior
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] behavior in
                self?.applyTerminalExitBehavior(behavior)
            }
    }

    private func applyTerminalExitBehavior(_ behavior: TerminalExitBehavior) {
        guard errorMessage == nil else { return }
        TairiLog.write("ghostty updating terminalExitBehavior=\(behavior.rawValue)")

        _ = withGhosttyConfig { config in
            for context in appContexts.values {
                if let app = context.app {
                    tairi_ghostty_app_update_config(app, config)
                }
            }

            for view in surfaces.values {
                if let surface = view.surface {
                    tairi_ghostty_surface_update_config(surface, config)
                }
            }

            return ()
        }
    }

    private func withGhosttyConfig<Result>(_ body: (ghostty_config_t) -> Result?) -> Result? {
        guard let config = tairi_ghostty_config_new() else {
            errorMessage = "ghostty_config_new failed"
            TairiLog.write(errorMessage ?? "ghostty_config_new failed")
            return nil
        }
        defer { tairi_ghostty_config_free(config) }

        tairi_ghostty_config_load_default_files(config)
        tairi_ghostty_config_load_recursive_files(config)
        applyTairiOverrides(to: config)
        tairi_ghostty_config_finalize(config)
        return body(config)
    }

    private func applyTairiOverrides(to config: ghostty_config_t) {
        let overrideURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tairi-\(UUID().uuidString).ghostty")
        let overrideContents = "wait-after-command = \(waitAfterCommandEnabled ? "true" : "false")\n"

        do {
            try overrideContents.write(to: overrideURL, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: overrideURL) }

            let path = overrideURL.path(percentEncoded: false)
            path.withCString { tairi_ghostty_config_load_file(config, $0) }
        } catch {
            TairiLog.write("ghostty override write failed: \(error.localizedDescription)")
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
        TairiLog.write(
            "ghostty disposing tile=\(tileID.uuidString) surfaceView=\(TairiLog.objectID(surfaceView)) surface=\(GhosttyRuntime.describeHandle(surfaceView.surface))"
        )
        surfaceView.dispose()

        guard let context = appContexts.removeValue(forKey: tileID) else { return }
        let contextPointer = Unmanaged.passUnretained(context).toOpaque()
        if let app = context.app {
            TairiLog.write(
                "ghostty freeing app tile=\(tileID.uuidString) context=\(TairiLog.pointer(contextPointer)) app=\(Self.describeHandle(app)) wakeups=\(context.wakeupCount)"
            )
            tairi_ghostty_app_free(app)
            context.app = nil
        }
        TairiLog.write("ghostty releasing context tile=\(tileID.uuidString) context=\(TairiLog.pointer(contextPointer))")
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
            _ = interactionController.addTerminalTile(
                nextTo: tileID,
                workingDirectory: spawnWorkingDirectory(for: tileID),
                transition: .preserveViewport
            )
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

    private func inheritedWorkingDirectory(for tileID: UUID) -> String? {
        guard let surface = surfaces[tileID]?.surface else {
            return nil
        }

        let inheritedConfig = tairi_ghostty_surface_inherited_config(surface, GHOSTTY_SURFACE_CONTEXT_WINDOW)
        guard let workingDirectory = inheritedConfig.working_directory,
              let path = String(validatingCString: workingDirectory),
              !path.isEmpty else {
            return nil
        }

        return path
    }

    private static let wakeup: ghostty_runtime_wakeup_cb = { userdata in
        guard let userdata else { return }
        let opaque = UInt(bitPattern: userdata)
        DispatchQueue.main.async {
            guard let rawPointer = UnsafeMutableRawPointer(bitPattern: opaque) else { return }
            let context = Unmanaged<AppContext>.fromOpaque(rawPointer).takeUnretainedValue()
            context.wakeupCount += 1
            if context.wakeupCount <= 5 || context.wakeupCount == 10 || context.wakeupCount.isMultiple(of: 100) {
                TairiLog.write(
                    "ghostty wakeup tile=\(context.tileID.uuidString) count=\(context.wakeupCount) context=\(TairiLog.pointer(rawPointer)) app=\(GhosttyRuntime.describeHandle(context.app))"
                )
            }
            if let app = context.app {
                tairi_ghostty_app_tick(app)
            } else if context.wakeupCount <= 5 {
                TairiLog.write(
                    "ghostty wakeup dropped tile=\(context.tileID.uuidString) count=\(context.wakeupCount) context=\(TairiLog.pointer(rawPointer)) app=nil"
                )
            }
        }
    }

    private static let action: ghostty_runtime_action_cb = { app, target, action in
        guard let userdata = tairi_ghostty_app_userdata(app) else {
            TairiLog.write("ghostty action dropped app=\(GhosttyRuntime.describeHandle(app)) reason=missing_userdata tag=\(action.tag.rawValue)")
            return false
        }
        let context = Unmanaged<AppContext>.fromOpaque(userdata).takeUnretainedValue()
        guard let runtime = context.runtime else {
            TairiLog.write(
                "ghostty action dropped tile=\(context.tileID.uuidString) context=\(TairiLog.pointer(userdata)) app=\(GhosttyRuntime.describeHandle(app)) reason=runtime_nil tag=\(action.tag.rawValue)"
            )
            return false
        }
        return runtime.handle(action: action, target: target)
    }

    private static let readClipboard: ghostty_runtime_read_clipboard_cb = { userdata, _, state in
        guard let userdata else {
            TairiLog.write("ghostty readClipboard dropped reason=missing_userdata")
            return false
        }
        let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
        guard let surface = view.surface else {
            TairiLog.write("ghostty readClipboard dropped tile=\(view.tileID.uuidString) reason=surface_nil")
            return false
        }
        guard let value = NSPasteboard.general.string(forType: .string) else {
            TairiLog.write("ghostty readClipboard empty tile=\(view.tileID.uuidString)")
            return false
        }
        value.withCString { ptr in
            tairi_ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
        }
        return true
    }

    private static let confirmReadClipboard: ghostty_runtime_confirm_read_clipboard_cb = { userdata, value, state, _ in
        guard let userdata, let value else { return }
        let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
        guard let surface = view.surface else {
            TairiLog.write("ghostty confirmReadClipboard dropped tile=\(view.tileID.uuidString) reason=surface_nil")
            return
        }
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

    private static func describeHandle(_ handle: UnsafeMutableRawPointer?) -> String {
        TairiLog.pointer(handle)
    }
}

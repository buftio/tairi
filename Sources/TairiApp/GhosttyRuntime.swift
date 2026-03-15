import AppKit
import Combine
import Foundation
import GhosttyDyn

enum DetachReason: String {
    case uiChurn = "ui_churn"
}

enum TerminateReason: String {
    case userClosedTile = "user_closed_tile"
    case workspaceRemoved = "workspace_removed"
    case exitBehaviorAutoClose = "exit_behavior_auto_close"
    case appShutdown = "app_shutdown"
}

@MainActor
final class GhosttyRuntime: ObservableObject {
    struct TileCloseAnimationContext {
        let workspaceID: UUID
        let insertionIndex: Int
        let snapshotWidth: CGFloat
        let gapWidth: CGFloat
        let snapshotImage: NSImage?
    }

    @Published var errorMessage: String?

    let store: WorkspaceStore
    let interactionController: WorkspaceInteractionController
    let settings: AppSettings
    let launchConfiguration: TairiLaunchConfiguration
    let actionAdapter = GhosttyActionAdapter()
    let sessionRegistry = GhosttySessionRegistry()
    var storeObserver: AnyCancellable?
    var settingsObserver: AnyCancellable?
    private var didInstallAppObservers = false
    var lastInputTileID: UUID?
    var lastInputAt: Date?
    private var pendingFocusedTileID: UUID?

    init(
        store: WorkspaceStore,
        interactionController: WorkspaceInteractionController,
        settings: AppSettings,
        launchConfiguration: TairiLaunchConfiguration
    ) {
        self.store = store
        self.interactionController = interactionController
        self.settings = settings
        self.launchConfiguration = launchConfiguration
        bootstrap()
        observeSettings()
        observeStore()
    }

    var waitAfterCommandEnabled: Bool {
        settings.terminalExitBehavior.waitAfterCommandEnabled
    }

    func createSession(workingDirectory: String) -> UUID {
        let sessionID = UUID()
        _ = ensureSessionExists(id: sessionID, workingDirectory: workingDirectory)
        return sessionID
    }

    @discardableResult
    func createTile(
        nextTo tileID: UUID? = nil,
        workingDirectory: String? = nil,
        transition: WorkspaceInteractionController.TileTransition = .animatedReveal
    ) -> WorkspaceStore.Tile {
        let resolvedWorkingDirectory = workingDirectory ?? spawnWorkingDirectory(for: tileID)
        let sessionID = createSession(workingDirectory: resolvedWorkingDirectory)
        let tile = interactionController.addTerminalTile(
            nextTo: tileID,
            workingDirectory: resolvedWorkingDirectory,
            sessionID: sessionID,
            transition: transition
        )
        sessionRegistry.setSessionID(sessionID, forTileID: tile.id)
        return tile
    }

    func attachTile(_ tileID: UUID, to containerView: NSView) {
        guard let tile = store.tile(tileID) else { return }
        guard let session = ensureSessionExists(
            id: tile.surface.terminalSessionID,
            workingDirectory: tile.pwd ?? TerminalWorkingDirectory.defaultDirectoryForEmptyWorkspace()
        ) else {
            return
        }

        if let previousTileID = session.attachedTileID, previousTileID != tileID {
            TairiLog.write(
                "ghostty session reattach session=\(session.id.uuidString) fromTile=\(previousTileID.uuidString) toTile=\(tileID.uuidString)"
            )
            session.surfaceView.removeFromSuperview()
        }

        session.attachedTileID = tileID
        sessionRegistry.setSessionID(session.id, forTileID: tileID)

        let surfaceView = session.surfaceView
        if surfaceView.superview !== containerView {
            surfaceView.removeFromSuperview()
            containerView.addSubview(surfaceView)
        }
        surfaceView.frame = containerView.bounds
        surfaceView.autoresizingMask = [.width, .height]

        TairiLog.write(
            "ghostty session attached session=\(session.id.uuidString) tile=\(tileID.uuidString) container=\(TairiLog.objectID(containerView))"
        )

        if pendingFocusedTileID == tileID {
            DispatchQueue.main.async { [weak self] in
                self?.focusSurface(tileID: tileID)
            }
        }
    }

    func detachTile(_ tileID: UUID, reason: DetachReason) {
        guard let session = session(for: tileID) else { return }
        session.surfaceView.removeFromSuperview()
        if session.attachedTileID == tileID {
            session.attachedTileID = nil
        }

        TairiLog.write(
            "ghostty session detached session=\(session.id.uuidString) tile=\(tileID.uuidString) reason=\(reason.rawValue)"
        )

        if case .exited = session.state {
            destroyDetachedExitedSession(sessionID: session.id, source: "detach")
        }
    }

    func terminateSession(for tileID: UUID, reason: TerminateReason) {
        guard let sessionID = sessionID(for: tileID) else { return }
        destroySession(sessionID: sessionID, reasonLabel: reason.rawValue, requestedTileID: tileID)
    }

    func closeTile(
        _ tileID: UUID,
        preferredVisibleMidX: CGFloat? = nil,
        stripLeadingInset: CGFloat = WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: false),
        transition: WorkspaceInteractionController.TileTransition = .animatedReveal,
        snapshotImage: NSImage? = nil
    ) {
        let closeAnimationContext = tileCloseAnimationContext(for: tileID, snapshotImage: snapshotImage)
        terminateSession(for: tileID, reason: .userClosedTile)
        finishClosingTile(
            tileID,
            preferredVisibleMidX: preferredVisibleMidX,
            stripLeadingInset: stripLeadingInset,
            transition: transition,
            closeAnimationContext: closeAnimationContext
        )
    }

    func terminateAllSessions(reason: TerminateReason) {
        for session in sessionRegistry.allSessions {
            destroySession(sessionID: session.id, reasonLabel: reason.rawValue, requestedTileID: session.attachedTileID)
        }
    }

    func focus(tileID: UUID, transition: WorkspaceInteractionController.TileTransition = .immediate) {
        interactionController.selectTile(tileID, transition: transition)
        focusSurface(tileID: tileID)
    }

    func didFocusSurface(sessionID: UUID) {
        guard let tileID = attachedTileID(for: sessionID) else { return }
        interactionController.selectTile(tileID)
    }

    func focusSurface(tileID: UUID) {
        guard let tile = store.tile(tileID) else { return }
        guard let session = ensureSessionExists(
            id: tile.surface.terminalSessionID,
            workingDirectory: tile.pwd ?? TerminalWorkingDirectory.defaultDirectoryForEmptyWorkspace()
        ) else {
            return
        }
        guard session.surfaceView.window != nil else {
            pendingFocusedTileID = tileID
            TairiLog.write("ghostty focus deferred tile=\(tileID.uuidString) session=\(session.id.uuidString)")
            return
        }
        if pendingFocusedTileID == tileID {
            pendingFocusedTileID = nil
        }
        session.surfaceView.focusSurface()
    }

    func finishClosingTile(
        _ tileID: UUID,
        preferredVisibleMidX: CGFloat? = nil,
        stripLeadingInset: CGFloat = WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: false),
        transition: WorkspaceInteractionController.TileTransition = .animatedReveal,
        closeAnimationContext: TileCloseAnimationContext? = nil
    ) {
        if let closeAnimationContext {
            interactionController.animateTileClose(
                workspaceID: closeAnimationContext.workspaceID,
                insertionIndex: closeAnimationContext.insertionIndex,
                snapshotWidth: closeAnimationContext.snapshotWidth,
                gapWidth: closeAnimationContext.gapWidth,
                animated: transition == .animatedReveal,
                snapshotImage: closeAnimationContext.snapshotImage
            )
        }
        let selectedTileID = store.closeTile(
            tileID,
            preferredVisibleMidX: preferredVisibleMidX,
            stripLeadingInset: stripLeadingInset
        )
        if let selectedTileID {
            interactionController.revealSelection(of: selectedTileID, transition: transition)
            focusSurface(tileID: selectedTileID)
        }
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

    func attachedTileID(for sessionID: UUID) -> UUID? {
        sessionRegistry.session(id: sessionID)?.attachedTileID
    }

    func tileCloseAnimationContext(for tileID: UUID, snapshotImage: NSImage? = nil) -> TileCloseAnimationContext? {
        guard let workspaceID = store.workspaceID(containing: tileID),
              let workspace = store.workspaces.first(where: { $0.id == workspaceID }),
              let tileIndex = workspace.tiles.firstIndex(where: { $0.id == tileID }) else {
            return nil
        }

        let hasTrailingTile = tileIndex < workspace.tiles.count - 1
        return TileCloseAnimationContext(
            workspaceID: workspaceID,
            insertionIndex: tileIndex,
            snapshotWidth: workspace.tiles[tileIndex].width,
            gapWidth: workspace.tiles[tileIndex].width
                + (hasTrailingTile ? WorkspaceCanvasLayoutMetrics.tileSpacing : 0),
            snapshotImage: snapshotImage
        )
    }

    private func bootstrap() {
        if let parseError = launchConfiguration.parseError {
            errorMessage = parseError
            TairiLog.write("launch configuration error: \(parseError)")
            return
        }

        configureBundledGhosttyPaths()
        TairiLog.write("bootstrap start")
        TairiLog.write("launch strips=\(launchConfiguration.layoutSummary)")
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

        let didInitialize = launchConfiguration.withGhosttyArguments { argc, argv in
            tairi_ghostty_init(argc, argv) == GHOSTTY_SUCCESS
        }

        if !didInitialize {
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

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.terminateAllSessions(reason: .appShutdown)
            }
        }
    }

    private func setAllAppsFocused(_ focused: Bool) {
        for session in sessionRegistry.allSessions {
            if let app = session.appContext.app {
                tairi_ghostty_app_set_focus(app, focused)
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
}

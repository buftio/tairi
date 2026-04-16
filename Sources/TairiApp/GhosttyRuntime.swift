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

    var requiresForceKill: Bool {
        switch self {
        case .userClosedTile, .workspaceRemoved, .appShutdown:
            true
        case .exitBehaviorAutoClose:
            false
        }
    }
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
    @Published var appTheme = GhosttyAppTheme.fallback

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
    private var focusedTileID: UUID?
    private var pendingFocusedTileID: UUID?
    private(set) var terminalCommand = "/bin/zsh"

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
        let resolvedWorkingDirectory =
            workingDirectory
            ?? store.preferredWorkingDirectoryForNewTile(
                nextTo: tileID,
                fallback: spawnWorkingDirectory(for: tileID)
            )
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

    @discardableResult
    func createGitTile(
        nextTo tileID: UUID? = nil,
        transition: WorkspaceInteractionController.TileTransition = .animatedReveal
    ) -> WorkspaceStore.Tile {
        interactionController.addGitTile(
            nextTo: tileID,
            transition: transition
        )
    }

    func attachTile(_ tileID: UUID, to containerView: NSView) {
        guard let tile = store.tile(tileID) else { return }
        guard tile.surface.isTerminal else { return }
        guard let sessionID = tile.surface.terminalSessionID else { return }
        guard
            let session = ensureSessionExists(
                id: sessionID,
                workingDirectory: tile.pwd ?? TerminalWorkingDirectory.defaultDirectoryForEmptyWorkspace()
            )
        else {
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
        forceTerminateSessionProcess(sessionID: sessionID, reason: reason)
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
        if store.tile(tileID)?.surface.isTerminal == true {
            terminateSession(for: tileID, reason: .userClosedTile)
        }
        finishClosingTile(
            tileID,
            preferredVisibleMidX: preferredVisibleMidX,
            stripLeadingInset: stripLeadingInset,
            transition: transition,
            closeAnimationContext: closeAnimationContext
        )
    }

    func removeWorkspace(_ workspaceID: UUID) {
        guard let workspace = store.workspaces.first(where: { $0.id == workspaceID }) else { return }

        let wasSelectedWorkspace = workspaceID == store.selectedWorkspaceID
        TairiLog.write(
            "ghostty removeWorkspace begin workspace=\(workspaceID.uuidString) tileCount=\(workspace.tiles.count) wasSelected=\(wasSelectedWorkspace)"
        )

        for tile in workspace.tiles where tile.surface.isTerminal {
            terminateSession(for: tile.id, reason: .workspaceRemoved)
        }

        let selectedTileID = store.removeWorkspace(workspaceID)

        if wasSelectedWorkspace {
            if let selectedTileID {
                interactionController.revealSelection(of: selectedTileID)
                focusSurface(tileID: selectedTileID)
            } else {
                interactionController.revealWorkspace(store.selectedWorkspaceID, animated: false)
            }
        }

        TairiLog.write(
            "ghostty removeWorkspace end workspace=\(workspaceID.uuidString) selectedWorkspace=\(store.selectedWorkspaceID.uuidString) selectedTile=\(selectedTileID?.uuidString ?? "none")"
        )
    }

    func terminateAllSessions(reason: TerminateReason) {
        for session in sessionRegistry.allSessions {
            forceTerminateSessionProcess(sessionID: session.id, reason: reason)
            destroySession(sessionID: session.id, reasonLabel: reason.rawValue, requestedTileID: session.attachedTileID)
        }
    }

    func focus(tileID: UUID, transition: WorkspaceInteractionController.TileTransition = .immediate) {
        TairiLog.write("ghostty focus request tile=\(tileID.uuidString) transition=\(String(describing: transition))")
        interactionController.selectTile(tileID, transition: transition)
        focusSurface(tileID: tileID)
    }

    func didFocusSurface(sessionID: UUID) {
        guard let tileID = attachedTileID(for: sessionID) else { return }
        focusedTileID = tileID
        pendingFocusedTileID = nil
        interactionController.selectTile(tileID)
    }

    func focusSurface(tileID: UUID) {
        TairiLog.write("ghostty focusSurface start tile=\(tileID.uuidString)")
        if pendingFocusedTileID != tileID {
            pendingFocusedTileID = nil
        }
        guard let tile = store.tile(tileID) else {
            TairiLog.write("ghostty focusSurface skipped tile=\(tileID.uuidString) reason=missing-tile")
            return
        }
        guard tile.surface.isTerminal else {
            focusedTileID = nil
            TairiLog.write("ghostty focusSurface skipped tile=\(tileID.uuidString) reason=non-terminal")
            return
        }
        guard let sessionID = tile.surface.terminalSessionID else {
            TairiLog.write("ghostty focusSurface skipped tile=\(tileID.uuidString) reason=missing-session-id")
            return
        }
        guard
            let session = ensureSessionExists(
                id: sessionID,
                workingDirectory: tile.pwd ?? TerminalWorkingDirectory.defaultDirectoryForEmptyWorkspace()
            )
        else {
            TairiLog.write(
                "ghostty focusSurface failed tile=\(tileID.uuidString) session=\(sessionID.uuidString) reason=missing-session"
            )
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
        TairiLog.write(
            "ghostty focusSurface proceed tile=\(tileID.uuidString) session=\(session.id.uuidString) surfaceView=\(TairiLog.objectID(session.surfaceView))"
        )
        session.surfaceView.focusSurface()
        TairiLog.write("ghostty focusSurface complete tile=\(tileID.uuidString) session=\(session.id.uuidString)")
    }

    func splitSelectedTileHorizontally() {
        let tileID = [pendingFocusedTileID, focusedTileID, store.selectedTileID]
            .compactMap { $0 }
            .first(where: { store.tile($0)?.surface.isTerminal == true })
        guard let tileID else { return }
        splitTileHorizontally(tileID: tileID)
    }

    func splitTileHorizontally(tileID: UUID) {
        guard store.tile(tileID)?.surface.isTerminal == true else {
            TairiLog.write("ghostty split shortcut skipped tile=\(tileID.uuidString) reason=missing-tile")
            return
        }
        let workingDirectory = spawnWorkingDirectory(for: tileID)
        let sessionID = createSession(workingDirectory: workingDirectory)
        guard
            let tile = interactionController.splitTerminalTile(
                tileID,
                workingDirectory: workingDirectory,
                sessionID: sessionID,
                transition: .animatedReveal
            )
        else {
            TairiLog.write("ghostty split shortcut skipped tile=\(tileID.uuidString) reason=split-failed")
            return
        }
        sessionRegistry.setSessionID(sessionID, forTileID: tile.id)
        TairiLog.write(
            "ghostty command split sourceTile=\(tileID.uuidString) newTile=\(tile.id.uuidString) session=\(sessionID.uuidString)"
        )
        focusSurface(tileID: tile.id)
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
            let tileIndex = workspace.tiles.firstIndex(where: { $0.id == tileID })
        else {
            return nil
        }

        let tile = workspace.tiles[tileIndex]
        let columnTileCount = workspace.tiles.filter { $0.columnID == tile.columnID }.count
        guard columnTileCount == 1 else { return nil }

        let columns = workspace.tiles.reduce(into: [UUID]()) { partialResult, tile in
            if partialResult.last != tile.columnID {
                partialResult.append(tile.columnID)
            }
        }
        guard let columnIndex = columns.firstIndex(of: tile.columnID) else { return nil }

        let hasTrailingTile = columnIndex < columns.count - 1
        return TileCloseAnimationContext(
            workspaceID: workspaceID,
            insertionIndex: columnIndex,
            snapshotWidth: tile.width,
            gapWidth: tile.width
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
        refreshTerminalCommand()
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

        refreshAppTheme()
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

        NotificationCenter.default.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.notifyKeyboardInputSourceChanged()
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

    private func notifyKeyboardInputSourceChanged() {
        let selectedInputSource = NSTextInputContext.current?.selectedKeyboardInputSource ?? "unknown"
        TairiLog.write(
            "ghostty keyboard input source changed selected=\(selectedInputSource) sessions=\(sessionRegistry.allSessions.count)"
        )

        for session in sessionRegistry.allSessions {
            if let app = session.appContext.app {
                tairi_ghostty_app_keyboard_changed(app)
            }
        }
    }

    private func configureBundledGhosttyPaths() {
        let resourcesURL = Bundle.main.resourceURL
        let bundledResources = resourcesURL?.appendingPathComponent("ghostty")
        let bundledBinary = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Frameworks/GhosttyRuntime.app/Contents/MacOS/ghostty")
        let vendoredVersion = TairiPaths.requiredGhosttyVendorVersionDirectory()
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

    func refreshTerminalCommand() {
        let resolvedCommand = GhosttyTerminalCommand.resolvedCommand(
            ghosttyBinaryPath: ProcessInfo.processInfo.environment["TAIRI_BUNDLED_GHOSTTY_BIN"]
        )
        terminalCommand = resolvedCommand
        TairiLog.write("ghostty terminal command resolved value=\(resolvedCommand.debugDescription)")
    }
}

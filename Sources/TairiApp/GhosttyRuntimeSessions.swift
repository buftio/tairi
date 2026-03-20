import AppKit
import Foundation
import GhosttyDyn

@MainActor
extension GhosttyRuntime {
    func observeStore() {
        storeObserver = store.$workspaces.sink { [weak self] workspaces in
            guard let self else { return }
            synchronizeSessions(with: workspaces)
        }
    }

    func synchronizeSessions(with workspaces: [WorkspaceStore.Workspace]) {
        guard errorMessage == nil else { return }

        let liveTiles = workspaces.flatMap(\.tiles)
        let liveTileIDs = Set(liveTiles.map(\.id))

        for tile in liveTiles {
            sessionRegistry.setSessionID(tile.surface.terminalSessionID, forTileID: tile.id)
            guard
                let session = ensureSessionExists(
                    id: tile.surface.terminalSessionID,
                    workingDirectory: tile.pwd ?? TerminalWorkingDirectory.defaultDirectoryForEmptyWorkspace()
                )
            else {
                continue
            }
            if session.pwd == nil, let pwd = tile.pwd, !pwd.isEmpty {
                session.updatePWD(pwd)
            }
        }

        let staleTileIDs = sessionRegistry.tileToSessionID.keys.filter { !liveTileIDs.contains($0) }
        for tileID in staleTileIDs {
            if let session = sessionRegistry.session(forTileID: tileID), session.attachedTileID == tileID {
                session.attachedTileID = nil
                session.surfaceView.removeFromSuperview()
                if case .exited = session.state {
                    destroyDetachedExitedSession(sessionID: session.id, source: "store_sync")
                }
            }
            sessionRegistry.clearTile(tileID)
        }
    }

    func observeSettings() {
        settingsObserver = settings.$terminalExitBehavior
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] behavior in
                self?.applyTerminalExitBehavior(behavior)
            }
    }

    func applyTerminalExitBehavior(_ behavior: TerminalExitBehavior) {
        guard errorMessage == nil else { return }
        TairiLog.write("ghostty updating terminalExitBehavior=\(behavior.rawValue)")

        _ = withGhosttyConfig { config in
            updateAllSessions(using: config)
            return ()
        }
    }

    func reloadConfiguration() {
        guard errorMessage == nil else { return }
        TairiLog.write("ghostty reloading configuration")

        _ = withGhosttyConfig { config in
            updateAllSessions(using: config)
            return ()
        }
    }

    func withGhosttyConfig<Result>(_ body: (ghostty_config_t) -> Result?) -> Result? {
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
        refreshAppTheme(using: config)
        return body(config)
    }

    func refreshAppTheme() {
        _ = withGhosttyConfig { _ in () }
    }

    func refreshAppTheme(using config: ghostty_config_t) {
        let resolvedTheme = GhosttyAppTheme(config: config)
        guard resolvedTheme != appTheme else { return }
        appTheme = resolvedTheme
        TairiLog.write(
            "ghostty theme updated background=\(appTheme.background.hexString) foreground=\(appTheme.foreground.hexString) accent=\(appTheme.accent.hexString)"
        )
    }

    private func updateAllSessions(using config: ghostty_config_t) {
        for session in sessionRegistry.allSessions {
            if let app = session.appContext.app {
                tairi_ghostty_app_update_config(app, config)
            }

            if let surface = session.surfaceView.surface {
                tairi_ghostty_surface_update_config(surface, config)
            }
        }
    }

    func applyTairiOverrides(to config: ghostty_config_t) {
        let overrideURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tairi-\(UUID().uuidString).ghostty")
        let overrideContents = """
            wait-after-command = \(waitAfterCommandEnabled ? "true" : "false")
            quit-after-last-window-closed = false
            bell-features = no-system
            """

        do {
            try overrideContents.write(to: overrideURL, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: overrideURL) }

            let path = overrideURL.path(percentEncoded: false)
            path.withCString { tairi_ghostty_config_load_file(config, $0) }
        } catch {
            TairiLog.write("ghostty override write failed: \(error.localizedDescription)")
        }
    }

    func createAppContext(for sessionID: UUID) -> GhosttyAppContext? {
        guard errorMessage == nil else { return nil }
        return withGhosttyConfig { config in
            let context = GhosttyAppContext(runtime: self, sessionID: sessionID)
            let retainedContext = Unmanaged.passRetained(context)
            let contextPointer = retainedContext.toOpaque()
            TairiLog.write(
                "ghostty creating app session=\(sessionID.uuidString) context=\(TairiLog.pointer(contextPointer)) selectedWorkspace=\(store.selectedWorkspaceID.uuidString) selectedTile=\(store.selectedTileID?.uuidString ?? "none")"
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
            TairiLog.write(
                "ghostty app created session=\(sessionID.uuidString) context=\(TairiLog.pointer(contextPointer)) app=\(Self.describeHandle(app))"
            )
            return context
        }
    }

    func ensureSessionExists(id sessionID: UUID, workingDirectory: String) -> GhosttySession? {
        if let session = sessionRegistry.session(id: sessionID) {
            if session.pwd == nil, !workingDirectory.isEmpty {
                session.updatePWD(workingDirectory)
            }
            return session
        }

        guard let appContext = createAppContext(for: sessionID), let app = appContext.app else {
            return nil
        }

        let surfaceView = GhosttySurfaceView(
            runtime: self,
            sessionID: sessionID,
            app: app,
            workingDirectory: workingDirectory
        )
        guard surfaceView.surface != nil else {
            releaseContext(appContext)
            errorMessage = "ghostty_surface_new failed"
            TairiLog.write(errorMessage ?? "ghostty_surface_new failed")
            return nil
        }

        let session = GhosttySession(
            id: sessionID,
            appContext: appContext,
            surfaceView: surfaceView,
            pwd: workingDirectory.isEmpty ? nil : workingDirectory
        )
        sessionRegistry.insert(session)
        TairiLog.write(
            "ghostty session created session=\(sessionID.uuidString) app=\(Self.describeHandle(app)) surface=\(Self.describeHandle(surfaceView.surface))"
        )
        return session
    }

    func destroySession(sessionID: UUID, reasonLabel: String, requestedTileID: UUID?) {
        guard let session = sessionRegistry.removeSession(id: sessionID) else { return }

        let removedTileIDs = sessionRegistry.removeTileMappings(forSessionID: sessionID)
        let tileLabel: String
        if let requestedTileID {
            tileLabel = requestedTileID.uuidString
        } else if let attachedTileID = session.attachedTileID {
            tileLabel = attachedTileID.uuidString
        } else if let firstRemovedTileID = removedTileIDs.first {
            tileLabel = firstRemovedTileID.uuidString
        } else {
            tileLabel = "none"
        }

        TairiLog.write(
            "ghostty session terminating session=\(sessionID.uuidString) tile=\(tileLabel) reason=\(reasonLabel) state=\(describe(state: session.state))"
        )

        session.surfaceView.dispose()

        if let app = session.appContext.app {
            TairiLog.write(
                "ghostty freeing app session=\(sessionID.uuidString) app=\(Self.describeHandle(app)) wakeups=\(session.appContext.wakeupCount)"
            )
            tairi_ghostty_app_free(app)
            session.appContext.app = nil
        }

        releaseContext(session.appContext)
    }

    func destroyDetachedExitedSession(sessionID: UUID, source: String) {
        guard let session = sessionRegistry.session(id: sessionID) else { return }
        guard session.attachedTileID == nil else { return }
        guard case .exited = session.state else { return }

        TairiLog.write(
            "ghostty detached session gc session=\(sessionID.uuidString) source=\(source) \(lifecycleSummary(for: sessionID))"
        )
        destroySession(sessionID: sessionID, reasonLabel: "detached_exit_gc", requestedTileID: nil)
    }

    func releaseContext(_ context: GhosttyAppContext) {
        let contextPointer = Unmanaged.passUnretained(context).toOpaque()
        TairiLog.write("ghostty releasing context session=\(context.sessionID.uuidString) context=\(TairiLog.pointer(contextPointer))")
        Unmanaged.passUnretained(context).release()
    }

    func lifecycleSummary(for sessionID: UUID, referenceDate: Date = Date()) -> String {
        sessionRegistry.session(id: sessionID)?.lifecycle.summary(referenceDate: referenceDate)
            ?? "title=\"shell\" pwd=\"none\" lastCommandFinished=none"
    }

    func logAction(_ tag: ghostty_action_tag_e, sessionID: UUID?, target: ghostty_target_s) {
        let targetLabel = target.tag == GHOSTTY_TARGET_SURFACE ? "surface" : "app"
        let sessionLabel = sessionID?.uuidString ?? "none"
        let tileLabel = sessionID.map { attachedTileID(for: $0)?.uuidString ?? "none" } ?? "none"
        TairiLog.write(
            "ghostty action \(GhosttyActionAdapter.actionName(tag)) target=\(targetLabel) session=\(sessionLabel) tile=\(tileLabel)"
        )
    }

    func shouldAcceptExit(for tileID: UUID, reason: String) -> Bool {
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

    func sessionID(for tileID: UUID) -> UUID? {
        store.tile(tileID)?.surface.terminalSessionID ?? sessionRegistry.sessionID(forTileID: tileID)
    }

    func session(for tileID: UUID) -> GhosttySession? {
        guard let sessionID = sessionID(for: tileID) else { return nil }
        return sessionRegistry.session(id: sessionID)
    }

    func sessionID(for target: ghostty_target_s) -> UUID? {
        guard target.tag == GHOSTTY_TARGET_SURFACE else { return nil }
        guard let userdata = tairi_ghostty_surface_userdata(target.target.surface) else { return nil }
        let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
        return view.sessionID
    }

    func handle(action: ghostty_action_s, target: ghostty_target_s, sourceSessionID: UUID) -> Bool {
        let sessionID = sessionID(for: target) ?? sourceSessionID
        logAction(action.tag, sessionID: sessionID, target: target)
        let event = actionAdapter.decode(action: action, sessionID: sessionID)
        return handle(event: event)
    }

    func handle(event: GhosttyRuntimeEvent) -> Bool {
        switch event {
        case .createTile(let sourceSessionID):
            let sourceTileID = attachedTileID(for: sourceSessionID)
            let tile = createTile(
                nextTo: sourceTileID,
                workingDirectory: spawnWorkingDirectory(for: sourceTileID),
                transition: .animatedReveal
            )
            focusSurface(tileID: tile.id)
            return true

        case .updateTitle(let sessionID, let title):
            guard let session = sessionRegistry.session(id: sessionID) else { return true }
            session.updateTitle(title)
            TairiLog.write("ghostty title update session=\(sessionID.uuidString) value=\(title.debugDescription)")
            if let tileID = session.attachedTileID {
                store.updateTitle(session.title, for: tileID)
            }
            return true

        case .updatePWD(let sessionID, let pwd):
            guard let session = sessionRegistry.session(id: sessionID) else { return true }
            session.updatePWD(pwd)
            TairiLog.write("ghostty pwd update session=\(sessionID.uuidString) value=\(pwd.debugDescription)")
            if let tileID = session.attachedTileID {
                store.updatePWD(pwd, for: tileID)
            }
            return true

        case .openURL(let url):
            NSWorkspace.shared.open(url)
            return true

        case .childExited(let sessionID, let exitCode, let reason):
            guard let session = sessionRegistry.session(id: sessionID) else { return true }
            session.state = .exited(exitCode: exitCode)
            TairiLog.write(
                "ghostty child exited session=\(sessionID.uuidString) tile=\(session.attachedTileID?.uuidString ?? "detached") exitCode=\(exitCode) reason=\(reason.rawValue) \(lifecycleSummary(for: sessionID))"
            )
            if session.attachedTileID == nil {
                destroyDetachedExitedSession(sessionID: sessionID, source: "child_exited")
            } else {
                TairiLog.write(
                    "ghostty keeping session=\(sessionID.uuidString) open until close_surface confirms the session ended"
                )
            }
            return true

        case .commandFinished(let sessionID, let exitCode):
            guard let session = sessionRegistry.session(id: sessionID) else { return true }
            session.recordCommandFinish(exitCode: exitCode)
            TairiLog.write(
                "ghostty command finished session=\(sessionID.uuidString) tile=\(session.attachedTileID?.uuidString ?? "detached") exitCode=\(exitCode) \(lifecycleSummary(for: sessionID))"
            )
            return true

        case .ignore:
            return true

        case .unhandled:
            return false
        }
    }

    func inheritedWorkingDirectory(for tileID: UUID) -> String? {
        guard let session = session(for: tileID),
            let surface = session.surfaceView.surface
        else {
            return nil
        }

        let inheritedConfig = tairi_ghostty_surface_inherited_config(surface, GHOSTTY_SURFACE_CONTEXT_WINDOW)
        guard let workingDirectory = inheritedConfig.working_directory,
            let path = String(validatingCString: workingDirectory),
            !path.isEmpty
        else {
            return nil
        }

        return path
    }
}

extension NSColor {
    fileprivate var hexString: String {
        let color = usingColorSpace(.sRGB) ?? self
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

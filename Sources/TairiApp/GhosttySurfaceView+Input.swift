import AppKit
import GhosttyDyn

@MainActor
extension GhosttySurfaceView {
    override func flagsChanged(with event: NSEvent) {
        sendMousePosition(event)
        super.flagsChanged(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        if interactionCoordinator?.scrollWheelRoutingDecision(for: event) == .interceptForWorkspaceHorizontalPan {
            return
        }

        guard let surface else { return }
        var deltaX = event.scrollingDeltaX
        var deltaY = event.scrollingDeltaY
        if event.hasPreciseScrollingDeltas {
            deltaX *= 2
            deltaY *= 2
        }

        tairi_ghostty_surface_mouse_scroll(surface, deltaX, deltaY, ghosttyScrollMods(from: event))
    }

    override func magnify(with event: NSEvent) {
        if interactionCoordinator?.handleMagnify(event, preferredTileID: attachedTileID) == true {
            return
        }
        super.magnify(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        sendMousePosition(event)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        sendMousePosition(event)
        super.mouseExited(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let zoomDirection = canvasZoomDirection(for: event),
            interactionCoordinator?.handleZoomKeyCommand(zoomDirection, preferredTileID: attachedTileID) == true
        {
            return
        }

        if let tileID = attachedTileID,
            let tileOffset = tileNavigationOffset(for: event),
            interactionCoordinator?.handleTileKeyNavigation(offset: tileOffset, from: tileID) == true
        {
            return
        }

        if let tileID = attachedTileID,
            let workspaceOffset = workspaceNavigationOffset(for: event),
            interactionCoordinator?.handleWorkspaceKeyNavigation(offset: workspaceOffset, from: tileID) == true
        {
            return
        }

        guard let surface else { return }
        if handleSplitShortcut(event, surface: surface) {
            return
        }
        recordInputIfAttached()

        var key = ghostty_input_key_s()
        key.action = GHOSTTY_ACTION_PRESS
        key.keycode = UInt32(event.keyCode)
        key.mods = ghosttyMods(from: event.modifierFlags)
        key.consumed_mods = ghosttyMods(from: event.modifierFlags.subtracting([.control, .command]))
        key.composing = false

        if let chars = event.characters(byApplyingModifiers: []), let scalar = chars.unicodeScalars.first {
            key.unshifted_codepoint = scalar.value
        }

        if let text = event.ghosttyCharacters {
            text.withCString { ptr in
                key.text = ptr
                _ = tairi_ghostty_surface_key(surface, key)
            }
        } else {
            _ = tairi_ghostty_surface_key(surface, key)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let surface else {
            return super.performKeyEquivalent(with: event)
        }
        if let direction = TairiHotkeys.tileReorderDirection(for: event),
            let tileID = Self.reorderTileID(
                attachedTileID: attachedTileID,
                selectedTileID: runtime.store.selectedTileID
            )
        {
            _ = interactionCoordinator?.handleTileReorderCommand(direction, from: tileID)
            return true
        }
        if window?.firstResponder === self,
            handleSplitShortcut(event, surface: surface)
        {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    static func reorderTileID(
        attachedTileID: UUID?,
        selectedTileID: UUID?
    ) -> UUID? {
        selectedTileID ?? attachedTileID
    }

    override func keyUp(with event: NSEvent) {
        if workspaceNavigationOffset(for: event) != nil
            || tileNavigationOffset(for: event) != nil
            || canvasZoomDirection(for: event) != nil
            || isHorizontalSplitShortcut(event)
        {
            return
        }

        guard let surface else { return }

        var key = ghostty_input_key_s()
        key.action = GHOSTTY_ACTION_RELEASE
        key.keycode = UInt32(event.keyCode)
        key.mods = ghosttyMods(from: event.modifierFlags)
        key.consumed_mods = ghosttyMods(from: event.modifierFlags.subtracting([.control, .command]))
        key.composing = false

        if let chars = event.characters(byApplyingModifiers: []), let scalar = chars.unicodeScalars.first {
            key.unshifted_codepoint = scalar.value
        }

        _ = tairi_ghostty_surface_key(surface, key)
    }

    @IBAction func copy(_ sender: Any?) {
        performBindingAction("copy_to_clipboard")
    }

    @IBAction func paste(_ sender: Any?) {
        performBindingAction("paste_from_clipboard")
    }

    @IBAction override func selectAll(_ sender: Any?) {
        performBindingAction("select_all")
    }

    private func workspaceNavigationOffset(for event: NSEvent) -> Int? {
        if TairiHotkeys.previousWorkspace.matches(event) {
            return -1
        }
        if TairiHotkeys.nextWorkspace.matches(event) {
            return 1
        }
        return nil
    }

    private func tileNavigationOffset(for event: NSEvent) -> Int? {
        if TairiHotkeys.previousTile.matches(event) {
            return -1
        }
        if TairiHotkeys.nextTile.matches(event) {
            return 1
        }
        return nil
    }

    private func canvasZoomDirection(for event: NSEvent) -> WorkspaceCanvasZoomController.Command? {
        if TairiHotkeys.zoomInSelection.matches(event) {
            return .zoomIn
        }
        if TairiHotkeys.zoomOutOverview.matches(event) {
            return .zoomOut
        }
        return nil
    }

    private func ghosttyScrollMods(from event: NSEvent) -> ghostty_input_scroll_mods_t {
        var value: Int32 = 0
        if event.hasPreciseScrollingDeltas {
            value |= 0b0000_0001
        }
        value |= Int32(ghosttyMomentum(from: event.momentumPhase).rawValue) << 1
        return value
    }

    private func ghosttyMomentum(from phase: NSEvent.Phase) -> ghostty_input_mouse_momentum_e {
        if phase.contains(.began) { return GHOSTTY_MOUSE_MOMENTUM_BEGAN }
        if phase.contains(.stationary) { return GHOSTTY_MOUSE_MOMENTUM_STATIONARY }
        if phase.contains(.changed) { return GHOSTTY_MOUSE_MOMENTUM_CHANGED }
        if phase.contains(.ended) { return GHOSTTY_MOUSE_MOMENTUM_ENDED }
        if phase.contains(.cancelled) { return GHOSTTY_MOUSE_MOMENTUM_CANCELLED }
        if phase.contains(.mayBegin) { return GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN }
        return GHOSTTY_MOUSE_MOMENTUM_NONE
    }

    func ghosttyMods(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var value = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { value |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { value |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { value |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { value |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { value |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(rawValue: value)
    }

    private func performBindingAction(_ action: String) {
        guard let surface else { return }
        action.withCString { ptr in
            _ = tairi_ghostty_surface_binding_action(surface, ptr, uintptr_t(action.lengthOfBytes(using: .utf8)))
        }
    }

    private func handleSplitShortcut(_ event: NSEvent, surface: ghostty_surface_t) -> Bool {
        guard isHorizontalSplitShortcut(event) else { return false }
        guard let tileID = attachedTileID else { return false }
        let _ = surface
        TairiLog.write("ghostty local split shortcut session=\(sessionID.uuidString) tile=\(tileID.uuidString)")
        runtime.splitTileHorizontally(tileID: tileID)
        return true
    }

    private func isHorizontalSplitShortcut(_ event: NSEvent) -> Bool {
        TairiHotkeys.splitHorizontally.matches(event)
    }

    func recordInputIfAttached() {
        guard let tileID = attachedTileID else { return }
        runtime.recordInput(for: tileID)
    }

    func focusAttachedTile(transition: WorkspaceInteractionController.TileTransition) {
        guard let tileID = attachedTileID else { return }
        runtime.focus(tileID: tileID, transition: transition)
    }
}

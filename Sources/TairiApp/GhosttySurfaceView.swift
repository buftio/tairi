import AppKit
import Foundation
import GhosttyDyn

extension NSEvent {
    var ghosttyCharacters: String? {
        guard let characters else { return nil }
        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
            }
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }
        return characters
    }
}

@MainActor
final class GhosttySurfaceView: NSView {
    struct TileCloseContext {
        let preferredVisibleMidX: CGFloat?
        let stripLeadingInset: CGFloat
        let snapshotImage: NSImage?
    }

    let runtime: GhosttyRuntime
    let sessionID: UUID

    private(set) var surface: ghostty_surface_t?
    private var trackingAreaRef: NSTrackingArea?
    private var lastLoggedBounds = CGSize.zero
    private var lastLoggedBacking = CGSize.zero
    private var lastLoggedScale = CGSize.zero
    private var lastLoggedDisplayID: UInt32?
    private var lastLoggedWindowNumber: Int?
    private static let terminalDiagnosticCommand: String? = {
        guard ProcessInfo.processInfo.environment["TAIRI_TERMINAL_DIAG"] == "1" else {
            return nil
        }

        let command = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/misc/diagnose-shell-session.zsh")
            .path(percentEncoded: false)
        return FileManager.default.isExecutableFile(atPath: command) ? command : nil
    }()

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(runtime: GhosttyRuntime, sessionID: UUID, app: ghostty_app_t?, workingDirectory: String) {
        self.runtime = runtime
        self.sessionID = sessionID
        super.init(frame: NSRect(x: 0, y: 0, width: 900, height: 640))
        logLifecycle("init begin frame=\(describe(size: frame.size))")

        var config = tairi_ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(self).toOpaque()
        ))
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2)

        if let app {
            workingDirectory.withCString { path in
                config.working_directory = path
                config.wait_after_command = runtime.waitAfterCommandEnabled
                config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW
                if let command = Self.terminalDiagnosticCommand {
                    TairiLog.write(
                        "ghostty diagnostic shell wrapper enabled session=\(sessionID.uuidString) command=\(command)"
                    )
                    command.withCString { commandCString in
                        config.command = commandCString
                        surface = tairi_ghostty_surface_new(app, &config)
                    }
                } else {
                    surface = tairi_ghostty_surface_new(app, &config)
                }
            }
        }

        logLifecycle(
            "init complete app=\(describeHandle(app)) surface=\(describeHandle(surface)) scaleFactor=\(String(format: "%.2f", config.scale_factor))"
        )

        syncScaleAndSize()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var attachedTileID: UUID? {
        runtime.attachedTileID(for: sessionID)
    }

    func dispose() {
        logLifecycle("dispose begin surface=\(describeHandle(surface))")
        removeFromSuperview()
        if let surface {
            tairi_ghostty_surface_free(surface)
            self.surface = nil
        }
        logLifecycle("dispose end surface=nil")
    }

    func focusSurface() {
        logLifecycle("focus requested window=\(describe(window: window))")
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let surface {
            logLifecycle("became first responder surface=\(describeHandle(surface))")
            runtime.didFocusSurface(sessionID: sessionID)
            tairi_ghostty_surface_set_focus(surface, true)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, let surface {
            logLifecycle("resigned first responder surface=\(describeHandle(surface))")
            tairi_ghostty_surface_set_focus(surface, false)
        }
        return result
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        logLifecycle("will move window from=\(describe(window: window)) to=\(describe(window: newWindow))")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        logWindowChangeIfNeeded(reason: "did move to window")
        syncDisplayID()
        syncScaleAndSize()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        let superviewID = superview.map { TairiLog.objectID($0) } ?? "nil"
        logLifecycle("did move superview superview=\(superviewID)")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncScaleAndSize()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncScaleAndSize()
    }

    override func mouseDown(with event: NSEvent) {
        if let tileID = attachedTileID,
           let canvasDocumentView = workspaceCanvasDocumentView(),
           canvasDocumentView.handleTileOverviewClick(tileID) {
            return
        }
        recordInputIfAttached()
        focusAttachedTile(transition: .animatedReveal)
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_LEFT)
    }

    override func mouseUp(with event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_LEFT)
    }

    override func rightMouseDown(with event: NSEvent) {
        recordInputIfAttached()
        focusAttachedTile(transition: .animatedReveal)
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_RIGHT)
    }

    override func rightMouseUp(with event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_RIGHT)
    }

    override func mouseMoved(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func mouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func scrollWheel(with event: NSEvent) {
        if let canvasDocumentView = workspaceCanvasDocumentView(), canvasDocumentView.handleScrollWheel(event) {
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
        if let canvasDocumentView = workspaceCanvasDocumentView(),
           canvasDocumentView.handleMagnify(event, preferredTileID: attachedTileID) {
            return
        }
        super.magnify(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let canvasDocumentView = workspaceCanvasDocumentView(),
           let zoomDirection = canvasZoomDirection(for: event),
           canvasDocumentView.handleZoomKeyCommand(zoomDirection, preferredTileID: attachedTileID) {
            return
        }

        if let canvasDocumentView = workspaceCanvasDocumentView(),
           let tileID = attachedTileID,
           let tileOffset = tileNavigationOffset(for: event),
           canvasDocumentView.handleTileKeyNavigation(offset: tileOffset, from: tileID) {
            return
        }

        if let canvasDocumentView = workspaceCanvasDocumentView(),
           let tileID = attachedTileID,
           let workspaceOffset = workspaceNavigationOffset(for: event),
           canvasDocumentView.handleWorkspaceKeyNavigation(offset: workspaceOffset, from: tileID) {
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
        if handleSplitShortcut(event, surface: surface) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if workspaceNavigationOffset(for: event) != nil
            || tileNavigationOffset(for: event) != nil
            || canvasZoomDirection(for: event) != nil
            || isHorizontalSplitShortcut(event) {
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

    private func sendMouseButton(
        _ event: NSEvent,
        state: ghostty_input_mouse_state_e,
        button: ghostty_input_mouse_button_e
    ) {
        guard let surface else { return }
        let mods = ghosttyMods(from: event.modifierFlags)
        _ = tairi_ghostty_surface_mouse_button(surface, state, button, mods)
        sendMousePosition(event)
    }

    private func sendMousePosition(_ event: NSEvent) {
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        let mods = ghosttyMods(from: event.modifierFlags)
        tairi_ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, mods)
    }

    private func syncScaleAndSize() {
        guard let surface else { return }
        let backing = convertToBacking(bounds)
        let xScale = bounds.width > 0 ? backing.width / bounds.width : 1
        let yScale = bounds.height > 0 ? backing.height / bounds.height : 1

        let didChange =
            lastLoggedBounds != bounds.size ||
            lastLoggedBacking != backing.size ||
            lastLoggedScale != CGSize(width: xScale, height: yScale)
        if didChange {
            logLifecycle(
                "syncScaleAndSize surface=\(describeHandle(surface)) bounds=\(describe(size: bounds.size)) backing=\(describe(size: backing.size)) scale=\(String(format: "%.3f", xScale))x\(String(format: "%.3f", yScale))"
            )
            lastLoggedBounds = bounds.size
            lastLoggedBacking = backing.size
            lastLoggedScale = CGSize(width: xScale, height: yScale)
        }

        tairi_ghostty_surface_set_content_scale(surface, xScale, yScale)
        tairi_ghostty_surface_set_size(surface, UInt32(max(backing.width, 1)), UInt32(max(backing.height, 1)))
    }

    private func syncDisplayID() {
        guard let surface,
              let screenNumber = window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return
        }
        if lastLoggedDisplayID != screenNumber.uint32Value {
            logLifecycle(
                "syncDisplayID surface=\(describeHandle(surface)) displayID=\(screenNumber.uint32Value) window=\(describe(window: window))"
            )
            lastLoggedDisplayID = screenNumber.uint32Value
        }
        tairi_ghostty_surface_set_display_id(surface, screenNumber.uint32Value)
    }

    private func workspaceCanvasDocumentView() -> WorkspaceCanvasDocumentView? {
        var ancestor = superview
        while let view = ancestor {
            if let documentView = view as? WorkspaceCanvasDocumentView {
                return documentView
            }
            ancestor = view.superview
        }
        return nil
    }

    private func workspaceTileHostView() -> WorkspaceTileHostView? {
        var ancestor = superview
        while let view = ancestor {
            if let tileHostView = view as? WorkspaceTileHostView {
                return tileHostView
            }
            ancestor = view.superview
        }
        return nil
    }

    func closeContext(for tileID: UUID) -> TileCloseContext? {
        guard let documentView = workspaceCanvasDocumentView() else { return nil }
        let workspaceID = runtime.store.workspaceID(containing: tileID) ?? runtime.store.selectedWorkspaceID
        return TileCloseContext(
            preferredVisibleMidX: documentView.visibleMidX(forWorkspaceID: workspaceID),
            stripLeadingInset: documentView.currentStripLeadingInset,
            snapshotImage: workspaceTileHostView()?.tairiSnapshotImage()
        )
    }

    private func workspaceNavigationOffset(for event: NSEvent) -> Int? {
        let requiredModifiers: NSEvent.ModifierFlags = [.option, .command]
        let activeModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard activeModifiers.contains(requiredModifiers) else { return nil }

        switch event.keyCode {
        case 126:
            return -1
        case 125:
            return 1
        default:
            return nil
        }
    }

    private func tileNavigationOffset(for event: NSEvent) -> Int? {
        let requiredModifiers: NSEvent.ModifierFlags = [.option, .command]
        let activeModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard activeModifiers.contains(requiredModifiers) else { return nil }

        switch event.keyCode {
        case 123:
            return -1
        case 124:
            return 1
        default:
            return nil
        }
    }

    private func canvasZoomDirection(for event: NSEvent) -> WorkspaceCanvasZoomController.Command? {
        let requiredModifiers: NSEvent.ModifierFlags = [.option, .command]
        let activeModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard activeModifiers.contains(requiredModifiers) else { return nil }

        switch event.keyCode {
        case 24, 69:
            return .zoomIn
        case 27, 78:
            return .zoomOut
        default:
            return nil
        }
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

    private func ghosttyMods(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
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

    private func recordInputIfAttached() {
        guard let tileID = attachedTileID else { return }
        runtime.recordInput(for: tileID)
    }

    private func focusAttachedTile(transition: WorkspaceInteractionController.TileTransition) {
        guard let tileID = attachedTileID else { return }
        runtime.focus(tileID: tileID, transition: transition)
    }

    private func logLifecycle(_ message: String) {
        let tileLabel = attachedTileID?.uuidString ?? "detached"
        TairiLog.write(
            "ghostty surface session=\(sessionID.uuidString) tile=\(tileLabel) view=\(TairiLog.objectID(self)) \(message)"
        )
    }

    private func logWindowChangeIfNeeded(reason: String) {
        let windowNumber = window?.windowNumber
        guard lastLoggedWindowNumber != windowNumber else { return }
        logLifecycle("\(reason) window=\(describe(window: window))")
        lastLoggedWindowNumber = windowNumber
    }

    private func describeHandle(_ handle: UnsafeMutableRawPointer?) -> String {
        TairiLog.pointer(handle)
    }

    private func describe(window: NSWindow?) -> String {
        guard let window else { return "nil" }
        return "#\(window.windowNumber)"
    }

    private func describe(size: CGSize) -> String {
        "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }
}

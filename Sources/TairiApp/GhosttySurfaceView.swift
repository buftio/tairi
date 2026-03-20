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
    var interactionCoordinator: GhosttySurfaceInteractionCoordinator?
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
           interactionCoordinator?.handleOverviewClick(tileID: tileID) == true {
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

    func closeContext(for tileID: UUID) -> TileCloseContext? {
        interactionCoordinator?.closeContext(for: tileID)
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

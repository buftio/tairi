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
    let runtime: GhosttyRuntime
    let tileID: UUID

    private(set) var surface: ghostty_surface_t?
    private var trackingAreaRef: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(runtime: GhosttyRuntime, tileID: UUID) {
        self.runtime = runtime
        self.tileID = tileID
        super.init(frame: NSRect(x: 0, y: 0, width: 900, height: 640))

        let app = runtime.app(for: tileID)
        var config = tairi_ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(self).toOpaque()
        ))
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2)

        if let app {
            let workingDirectory = FileManager.default.currentDirectoryPath
            workingDirectory.withCString { path in
                config.working_directory = path
                config.wait_after_command = true
                config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW
                surface = tairi_ghostty_surface_new(app, &config)
            }
        }

        syncScaleAndSize()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func dispose() {
        removeFromSuperview()
        if let surface {
            tairi_ghostty_surface_free(surface)
            self.surface = nil
        }
    }

    func focusSurface() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let surface {
            runtime.focus(tileID: tileID)
            tairi_ghostty_surface_set_focus(surface, true)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, let surface {
            tairi_ghostty_surface_set_focus(surface, false)
        }
        return result
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncDisplayID()
        syncScaleAndSize()
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
        runtime.recordInput(for: tileID)
        focusSurface()
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_LEFT)
    }

    override func mouseUp(with event: NSEvent) {
        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_LEFT)
    }

    override func rightMouseDown(with event: NSEvent) {
        runtime.recordInput(for: tileID)
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
        guard let surface else { return }
        let mods = ghosttyMods(from: event.modifierFlags)
        tairi_ghostty_surface_mouse_scroll(surface, event.scrollingDeltaX, event.scrollingDeltaY, Int32(bitPattern: mods.rawValue))
    }

    override func keyDown(with event: NSEvent) {
        guard let surface else { return }
        runtime.recordInput(for: tileID)

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

    override func keyUp(with event: NSEvent) {
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
        tairi_ghostty_surface_mouse_pos(surface, point.x, point.y, mods)
    }

    private func syncScaleAndSize() {
        guard let surface else { return }
        let backing = convertToBacking(bounds)
        let xScale = bounds.width > 0 ? backing.width / bounds.width : 1
        let yScale = bounds.height > 0 ? backing.height / bounds.height : 1
        tairi_ghostty_surface_set_content_scale(surface, xScale, yScale)
        tairi_ghostty_surface_set_size(surface, UInt32(max(backing.width, 1)), UInt32(max(backing.height, 1)))
    }

    private func syncDisplayID() {
        guard let surface, let screenNumber = window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return
        }
        tairi_ghostty_surface_set_display_id(surface, screenNumber.uint32Value)
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
}

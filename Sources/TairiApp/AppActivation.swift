import AppKit

@MainActor
enum AppActivation {
    static func bringAppToFront() {
        NSApp.setActivationPolicy(.regular)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
    }
}

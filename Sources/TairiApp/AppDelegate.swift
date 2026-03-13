import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        activateApp()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        activateApp()
    }

    private func activateApp() {
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            NSApp.windows.forEach { window in
                window.orderFrontRegardless()
                window.makeKey()
            }
            NSApp.mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.keyWindow?.makeKey()
        }
    }
}

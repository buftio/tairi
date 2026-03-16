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

    func applicationWillTerminate(_ notification: Notification) {
        TairiCrashReporter.shared.markCleanShutdown()
    }

    private func activateApp() {
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            if let keyWindow = NSApp.keyWindow {
                keyWindow.makeKeyAndOrderFront(nil)
                return
            }

            if let frontWindow = NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) {
                frontWindow.makeKeyAndOrderFront(nil)
            }
        }
    }
}

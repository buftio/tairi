import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        activateApp()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        activateApp()
    }

    func applicationWillTerminate(_ notification: Notification) {
        TairiCrashReporter.shared.markCleanShutdown()
    }

    private func activateApp() {
        AppActivation.bringAppToFront()

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

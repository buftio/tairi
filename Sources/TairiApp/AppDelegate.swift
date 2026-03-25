import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var didRegisterLifecycleObservers = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        TairiLog.write("app delegate willFinishLaunching windows=\(NSApp.windows.count)")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        TairiHostDiagnostics.logLaunchContext()
        registerLifecycleObserversIfNeeded()
        TairiLog.write("app delegate didFinishLaunching windows=\(NSApp.windows.count)")
        activateApp()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        TairiLog.write("app delegate didBecomeActive windows=\(NSApp.windows.count)")
        activateApp()
    }

    func applicationDidResignActive(_ notification: Notification) {
        TairiLog.write("app delegate didResignActive windows=\(NSApp.windows.count)")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        TairiLog.write(
            "app delegate shouldTerminate windows=\(sender.windows.count) visible=\(sender.windows.filter { $0.isVisible }.count)"
        )
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        TairiLog.write(
            "app delegate shouldTerminateAfterLastWindowClosed windows=\(sender.windows.count) visible=\(sender.windows.filter { $0.isVisible }.count)"
        )
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        TairiLog.write(
            "app delegate shouldHandleReopen hasVisibleWindows=\(flag) windows=\(sender.windows.count)"
        )
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        TairiLog.write("app delegate willTerminate windows=\(NSApp.windows.count)")
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

    private func registerLifecycleObserversIfNeeded() {
        guard !didRegisterLifecycleObservers else { return }
        didRegisterLifecycleObservers = true

        let center = NotificationCenter.default
        let appNotifications: [Notification.Name] = [
            NSApplication.willHideNotification,
            NSApplication.didHideNotification,
            NSApplication.willUnhideNotification,
            NSApplication.didUnhideNotification,
        ]
        let windowNotifications: [Notification.Name] = [
            NSWindow.willCloseNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
        ]

        for name in appNotifications {
            center.addObserver(
                self,
                selector: #selector(handleApplicationLifecycleNotification(_:)),
                name: name,
                object: nil
            )
        }

        for name in windowNotifications {
            center.addObserver(
                self,
                selector: #selector(handleWindowLifecycleNotification(_:)),
                name: name,
                object: nil
            )
        }
    }

    @objc
    private func handleApplicationLifecycleNotification(_ notification: Notification) {
        TairiLog.write(
            "app lifecycle notification name=\(notification.name.rawValue) windows=\(NSApp.windows.count) visible=\(NSApp.windows.filter { $0.isVisible }.count)"
        )
    }

    @objc
    private func handleWindowLifecycleNotification(_ notification: Notification) {
        let window = notification.object as? NSWindow
        let windowNumber = window?.windowNumber ?? -1
        let isVisible = window?.isVisible ?? false
        TairiLog.write(
            "window lifecycle notification name=\(notification.name.rawValue) window=\(windowNumber) visible=\(isVisible) key=\(window?.isKeyWindow ?? false) windows=\(NSApp.windows.count)"
        )
    }
}

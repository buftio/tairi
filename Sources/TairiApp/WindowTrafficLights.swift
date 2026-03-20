import AppKit
import SwiftUI

enum WindowTrafficLightsMetrics {
    static let leadingInsetWhenSidebarHidden: CGFloat = 14
    static let leadingInsetInsideSidebar: CGFloat = 12
    static let topInsetWhenSidebarHidden: CGFloat = 14
    static let topInsetInsideSidebar: CGFloat = 20
    static let spacing: CGFloat = 6
    static let hoverAreaWidth: CGFloat = 72
    static let hoverAreaHeight: CGFloat = 44
}

struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onResolve(window)
            }
        }
    }
}

struct WindowTrafficLightsHoverRegion: NSViewRepresentable {
    let isActive: Bool
    let onHoverChange: (Bool) -> Void

    func makeNSView(context: Context) -> HoverTrackingView {
        let view = HoverTrackingView()
        view.onHoverChange = onHoverChange
        view.isActive = isActive
        return view
    }

    func updateNSView(_ nsView: HoverTrackingView, context: Context) {
        nsView.onHoverChange = onHoverChange
        nsView.isActive = isActive
    }
}

final class HoverTrackingView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            if !isActive, isHovering {
                isHovering = false
                onHoverChange?(false)
            }
            needsLayout = true
            updateTrackingAreas()
        }
    }

    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        guard isActive else {
            trackingArea = nil
            return
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        guard isActive, !isHovering else { return }
        isHovering = true
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard isHovering else { return }
        isHovering = false
        onHoverChange?(false)
    }
}

@MainActor
final class WindowTrafficLightsController: NSObject, ObservableObject {
    private weak var window: NSWindow?
    private var lastObservedButtonIDs: [ObjectIdentifier] = []
    private var isApplyingLayout = false
    private var deferredLayoutGeneration = 0

    private var sidebarHidden = false
    private var isHovering = false
    private var sidebarLeadingInset: CGFloat = 0
    private var animationPolicy: AppAnimationPolicy = .defaultValue

    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        lastObservedButtonIDs = []
        clearObservers()
        registerWindowObservers(for: window)
    }

    func sync(
        sidebarHidden: Bool,
        isHovering: Bool,
        sidebarLeadingInset: CGFloat,
        animationPolicy: AppAnimationPolicy,
        in window: NSWindow
    ) {
        attach(to: window)
        self.sidebarHidden = sidebarHidden
        self.isHovering = isHovering
        self.sidebarLeadingInset = sidebarLeadingInset
        self.animationPolicy = animationPolicy

        applyLayout(in: window, animated: true)
        scheduleDeferredLayout(in: window)
    }

    private func registerWindowObservers(for window: NSWindow) {
        let notificationCenter = NotificationCenter.default
        let notifications: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didEndLiveResizeNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification
        ]

        for name in notifications {
            notificationCenter.addObserver(
                self,
                selector: #selector(handleObservedLayoutChange(_:)),
                name: name,
                object: window
            )
        }
    }

    private func registerButtonObservers(buttons: [NSButton], container: NSView) {
        let buttonIDs = buttons.map(ObjectIdentifier.init)
        guard buttonIDs != lastObservedButtonIDs else { return }
        guard let observedWindow = container.window ?? window else { return }

        clearObservers(keepingWindow: true)
        registerWindowObservers(for: observedWindow)

        let notificationCenter = NotificationCenter.default
        container.postsFrameChangedNotifications = true
        container.postsBoundsChangedNotifications = true

        let containerNotifications: [Notification.Name] = [
            NSView.frameDidChangeNotification,
            NSView.boundsDidChangeNotification
        ]

        for name in containerNotifications {
            notificationCenter.addObserver(
                self,
                selector: #selector(handleObservedLayoutChange(_:)),
                name: name,
                object: container
            )
        }

        for button in buttons {
            button.postsFrameChangedNotifications = true
            notificationCenter.addObserver(
                self,
                selector: #selector(handleObservedLayoutChange(_:)),
                name: NSView.frameDidChangeNotification,
                object: button
            )
        }

        lastObservedButtonIDs = buttonIDs
    }

    private func clearObservers(keepingWindow: Bool = false) {
        NotificationCenter.default.removeObserver(self)
        if !keepingWindow {
            lastObservedButtonIDs = []
        }
    }

    @objc
    private func handleObservedLayoutChange(_ notification: Notification) {
        resyncIfNeeded()
    }

    private func resyncIfNeeded() {
        guard !isApplyingLayout, let window else { return }
        applyLayout(in: window, animated: false)
    }

    private func scheduleDeferredLayout(in window: NSWindow) {
        deferredLayoutGeneration += 1
        let generation = deferredLayoutGeneration
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self,
                  let window,
                  self.window === window,
                  self.deferredLayoutGeneration == generation else {
                return
            }

            self.applyLayout(in: window, animated: false)
        }
    }

    private func applyLayout(in window: NSWindow, animated: Bool) {
        let buttons = trafficLightButtons(in: window)
        guard
            let firstButton = buttons.first,
            let buttonContainer = firstButton.superview
        else {
            return
        }

        registerButtonObservers(buttons: buttons, container: buttonContainer)
        buttonContainer.layoutSubtreeIfNeeded()

        if window.styleMask.contains(.fullScreen) {
            syncVisibility(for: buttons, animated: animated, forceVisible: true)
            return
        }

        let startX = sidebarHidden
            ? WindowTrafficLightsMetrics.leadingInsetWhenSidebarHidden
            : sidebarLeadingInset + WindowTrafficLightsMetrics.leadingInsetInsideSidebar
        let topInset = sidebarHidden
            ? WindowTrafficLightsMetrics.topInsetWhenSidebarHidden
            : WindowTrafficLightsMetrics.topInsetInsideSidebar
        let y = buttonContainer.bounds.height - topInset - firstButton.frame.height

        isApplyingLayout = true
        defer { isApplyingLayout = false }

        var x = startX
        for button in buttons {
            button.setFrameOrigin(NSPoint(x: x, y: y))
            x += button.frame.width + WindowTrafficLightsMetrics.spacing
        }

        syncVisibility(for: buttons, animated: animated)
    }

    private func trafficLightButtons(in window: NSWindow) -> [NSButton] {
        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        return buttonTypes.compactMap { window.standardWindowButton($0) }
    }

    private func syncVisibility(for buttons: [NSButton], animated: Bool, forceVisible: Bool = false) {
        let shouldReveal = forceVisible || !sidebarHidden || isHovering
        let targetAlpha: CGFloat = shouldReveal ? 1 : 0
        let needsUpdate = buttons.contains { button in
            abs(button.alphaValue - targetAlpha) > 0.01 || button.isEnabled != shouldReveal
        }

        guard needsUpdate else { return }

        for button in buttons {
            button.isEnabled = shouldReveal
            if animationPolicy.shouldAnimate(animated), shouldReveal, button.alphaValue < 0.99 {
                button.alphaValue = 0
            }
        }

        guard animationPolicy.shouldAnimate(animated) else {
            for button in buttons {
                button.alphaValue = targetAlpha
            }
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationPolicy.scaledDuration(0.18)
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for button in buttons {
                button.animator().alphaValue = targetAlpha
            }
        }
    }
}

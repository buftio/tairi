import Foundation

@MainActor
final class WindowChromeController: ObservableObject {
    private enum Metrics {
        static let toggleAnimationDuration: TimeInterval = 0.28
    }

    @Published private(set) var isSidebarHidden: Bool
    @Published private(set) var renderedStripLeadingInset: CGFloat

    private let settings: AppSettings
    private var stripLeadingInsetAnimationStartedAt = Date.distantPast
    private var stripLeadingInsetAnimationStartValue: CGFloat
    private var stripLeadingInsetAnimationTargetValue: CGFloat
    private var stripLeadingInsetAnimationTimer: Timer?

    init(settings: AppSettings) {
        self.settings = settings
        let initialSidebarHidden = settings.sidebarHidden
        isSidebarHidden = initialSidebarHidden
        let initialInset = WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: initialSidebarHidden)
        renderedStripLeadingInset = initialInset
        stripLeadingInsetAnimationStartValue = initialInset
        stripLeadingInsetAnimationTargetValue = initialInset
    }

    func toggleSidebarVisibility() {
        isSidebarHidden.toggle()
        settings.sidebarHidden = isSidebarHidden
        animateStripLeadingInset(
            to: WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: isSidebarHidden)
        )
    }

    private func animateStripLeadingInset(to targetInset: CGFloat) {
        guard abs(renderedStripLeadingInset - targetInset) > 0.5 else {
            renderedStripLeadingInset = targetInset
            stopStripLeadingInsetAnimation()
            return
        }

        guard settings.animationPolicy.shouldAnimate() else {
            renderedStripLeadingInset = targetInset
            stopStripLeadingInsetAnimation()
            return
        }

        stripLeadingInsetAnimationStartValue = renderedStripLeadingInset
        stripLeadingInsetAnimationTargetValue = targetInset
        stripLeadingInsetAnimationStartedAt = Date()

        stripLeadingInsetAnimationTimer?.invalidate()
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.stepStripLeadingInsetAnimation()
            }
        }
        stripLeadingInsetAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stepStripLeadingInsetAnimation() {
        let elapsed = Date().timeIntervalSince(stripLeadingInsetAnimationStartedAt)
        let duration = settings.animationPolicy.scaledDuration(Metrics.toggleAnimationDuration)
        guard duration > 0 else {
            stopStripLeadingInsetAnimation()
            return
        }
        let progress = min(max(elapsed / duration, 0), 1)
        let eased = 1 - pow(1 - progress, 3)
        renderedStripLeadingInset = stripLeadingInsetAnimationStartValue
            + (stripLeadingInsetAnimationTargetValue - stripLeadingInsetAnimationStartValue) * eased

        if progress >= 1 {
            stopStripLeadingInsetAnimation()
        }
    }

    private func stopStripLeadingInsetAnimation() {
        renderedStripLeadingInset = stripLeadingInsetAnimationTargetValue
        stripLeadingInsetAnimationTimer?.invalidate()
        stripLeadingInsetAnimationTimer = nil
    }
}

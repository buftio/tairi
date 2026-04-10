import AppKit
import Foundation

@MainActor
final class WorkspaceCanvasZoomController {
    enum Command {
        case zoomIn
        case zoomOut
    }

    private enum Metrics {
        static let workspacePeek: CGFloat = 72
        static let animationDuration: TimeInterval = 0.18
        static let magnifyTriggerThreshold: CGFloat = 0.08
        static let minimumOverviewScale: CGFloat = 0.14
    }

    var onChange: (() -> Void)?
    var animationPolicy: AppAnimationPolicy = .defaultValue {
        didSet {
            guard animationPolicy != oldValue else { return }
            guard !animationPolicy.effectiveAnimationsEnabled else { return }
            renderedOverviewProgress = targetOverviewProgress
            stopAnimation()
            onChange?()
        }
    }

    private(set) var renderedOverviewProgress: CGFloat = 0

    private var targetOverviewProgress: CGFloat = 0
    private var animationStartProgress: CGFloat = 0
    private var animationStartedAt = Date.distantPast
    private var animationTimer: Timer?

    private var lastMagnifyEventAt = Date.distantPast
    private var magnifyAccumulator: CGFloat = 0
    private var triggeredDuringCurrentMagnifyGesture = false

    func sync(
        mode: WorkspaceInteractionController.CanvasZoomMode,
        animated: Bool
    ) {
        let nextProgress: CGFloat = mode == .overview ? 1 : 0
        guard
            abs(targetOverviewProgress - nextProgress) > 0.001
                || abs(renderedOverviewProgress - nextProgress) > 0.001
        else {
            targetOverviewProgress = nextProgress
            renderedOverviewProgress = nextProgress
            stopAnimation()
            return
        }

        targetOverviewProgress = nextProgress

        guard animationPolicy.shouldAnimate(animated) else {
            renderedOverviewProgress = nextProgress
            stopAnimation()
            onChange?()
            return
        }

        animationStartProgress = renderedOverviewProgress
        animationStartedAt = Date()

        animationTimer?.invalidate()
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.stepAnimation()
            }
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func scale(
        mode: WorkspaceInteractionController.CanvasZoomMode,
        viewportSize: CGSize,
        workspaces: [WorkspaceStore.Workspace],
        stripLeadingInset: CGFloat
    ) -> CGFloat {
        let overviewScale = overviewScale(
            viewportSize: viewportSize,
            workspaces: workspaces,
            stripLeadingInset: stripLeadingInset
        )
        return 1 + ((overviewScale - 1) * renderedOverviewProgress)
    }

    func effectiveHorizontalOffset(_ offset: CGFloat) -> CGFloat {
        offset * (1 - renderedOverviewProgress)
    }

    var isOverviewPresented: Bool {
        renderedOverviewProgress > 0.001 || targetOverviewProgress > 0.001
    }

    func handleMagnify(
        _ event: NSEvent,
        mode: WorkspaceInteractionController.CanvasZoomMode,
        preferredTileID: UUID?,
        perform: (Command, UUID?) -> Void
    ) -> Bool {
        resetMagnifyGestureIfNeeded(for: event)
        magnifyAccumulator += event.magnification

        if !triggeredDuringCurrentMagnifyGesture {
            switch mode {
            case .focused where magnifyAccumulator <= -Metrics.magnifyTriggerThreshold:
                perform(.zoomOut, nil)
                triggeredDuringCurrentMagnifyGesture = true
            case .overview where magnifyAccumulator >= Metrics.magnifyTriggerThreshold:
                perform(.zoomIn, preferredTileID)
                triggeredDuringCurrentMagnifyGesture = true
            default:
                break
            }
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            resetMagnifyGestureState()
        }

        return true
    }

    private func overviewScale(
        viewportSize: CGSize,
        workspaces: [WorkspaceStore.Workspace],
        stripLeadingInset: CGFloat
    ) -> CGFloat {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return 1 }

        let overviewWorkspaces = Self.overviewWorkspaces(from: workspaces)
        let maxWorkspaceTileSpan = overviewWorkspaces.map(rawTileSpan(for:)).max() ?? 0
        let availableWidth = max(
            viewportSize.width
                - stripLeadingInset
                - (WorkspaceCanvasLayoutMetrics.horizontalPadding * 2),
            1
        )
        let widthScale = maxWorkspaceTileSpan > 0 ? min(availableWidth / maxWorkspaceTileSpan, 1) : 1

        let baseTileHeight = max(
            viewportSize.height
                - (Metrics.workspacePeek * 2)
                - (WorkspaceCanvasLayoutMetrics.verticalPadding * 2),
            WorkspaceCanvasLayoutMetrics.minimumTileHeight
        )
        let baseRowHeight = baseTileHeight + (WorkspaceCanvasLayoutMetrics.verticalPadding * 2)
        let totalHeight =
            baseRowHeight * CGFloat(overviewWorkspaces.count)
            + WorkspaceCanvasLayoutMetrics.rowSpacing * CGFloat(max(overviewWorkspaces.count - 1, 0))
        let heightScale = totalHeight > 0 ? min(viewportSize.height / totalHeight, 1) : 1

        return max(min(widthScale, heightScale), Metrics.minimumOverviewScale)
    }

    static func overviewWorkspaces(
        from workspaces: [WorkspaceStore.Workspace]
    ) -> [WorkspaceStore.Workspace] {
        guard let lastWorkspaceWithTiles = workspaces.lastIndex(where: { !$0.tiles.isEmpty }) else {
            return []
        }
        return Array(workspaces[...lastWorkspaceWithTiles])
    }

    private func rawTileSpan(for workspace: WorkspaceStore.Workspace) -> CGFloat {
        WorkspaceColumnLayout.rawTileSpan(for: workspace)
    }

    private func stepAnimation() {
        let elapsed = Date().timeIntervalSince(animationStartedAt)
        let duration = animationPolicy.scaledDuration(Metrics.animationDuration)
        guard duration > 0 else {
            renderedOverviewProgress = targetOverviewProgress
            stopAnimation()
            onChange?()
            return
        }
        let progress = min(max(elapsed / duration, 0), 1)
        let eased = 1 - pow(1 - progress, 3)
        renderedOverviewProgress =
            animationStartProgress
            + ((targetOverviewProgress - animationStartProgress) * eased)
        onChange?()

        if progress >= 1 {
            renderedOverviewProgress = targetOverviewProgress
            stopAnimation()
            if targetOverviewProgress > 0.999 {
                onChange?()
            }
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func resetMagnifyGestureIfNeeded(for event: NSEvent) {
        let now = Date()
        let phaseBegan = event.phase.contains(.began) || event.phase.contains(.mayBegin)
        let timedOut = now.timeIntervalSince(lastMagnifyEventAt) > 0.25
        if phaseBegan || timedOut {
            resetMagnifyGestureState()
        }
        lastMagnifyEventAt = now
    }

    private func resetMagnifyGestureState() {
        magnifyAccumulator = 0
        triggeredDuringCurrentMagnifyGesture = false
    }
}

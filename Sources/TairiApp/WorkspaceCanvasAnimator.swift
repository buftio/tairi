import Foundation

@MainActor
final class WorkspaceCanvasAnimator {
    private enum Metrics {
        static let horizontalRevealAnimationDuration: TimeInterval = 0.2
    }

    var onChange: (() -> Void)?

    private var renderedHorizontalOffsets: [UUID: CGFloat] = [:]
    private var pendingAnimatedRevealWorkspaceID: UUID?
    private var animatingWorkspaceID: UUID?
    private var horizontalRevealAnimationStartOffset: CGFloat = 0
    private var horizontalRevealAnimationTargetOffset: CGFloat = 0
    private var horizontalRevealAnimationStartedAt = Date.distantPast
    private var horizontalRevealAnimationTimer: Timer?

    func pruneOffsets(workspaces: [WorkspaceStore.Workspace]) {
        renderedHorizontalOffsets = renderedHorizontalOffsets.filter { entry in
            workspaces.contains(where: { $0.id == entry.key })
        }
    }

    func queueReveal(for tileID: UUID, animated: Bool, in workspaces: [WorkspaceStore.Workspace]) {
        guard animated else {
            pendingAnimatedRevealWorkspaceID = nil
            return
        }

        pendingAnimatedRevealWorkspaceID = workspaces.first(where: { workspace in
            workspace.tiles.contains(where: { $0.id == tileID })
        })?.id
    }

    func effectiveHorizontalOffset(for workspace: WorkspaceStore.Workspace) -> CGFloat {
        renderedHorizontalOffsets[workspace.id] ?? workspace.horizontalOffset
    }

    func syncRenderedHorizontalOffsets(for workspaces: [WorkspaceStore.Workspace]) {
        guard let pendingAnimatedRevealWorkspaceID else {
            stopHorizontalRevealAnimation()
            for workspace in workspaces {
                renderedHorizontalOffsets[workspace.id] = workspace.horizontalOffset
            }
            return
        }

        for workspace in workspaces where workspace.id != pendingAnimatedRevealWorkspaceID {
            renderedHorizontalOffsets[workspace.id] = workspace.horizontalOffset
        }

        guard let workspace = workspaces.first(where: { $0.id == pendingAnimatedRevealWorkspaceID }) else {
            self.pendingAnimatedRevealWorkspaceID = nil
            stopHorizontalRevealAnimation()
            return
        }

        let startOffset = renderedHorizontalOffsets[workspace.id] ?? workspace.horizontalOffset
        let targetOffset = workspace.horizontalOffset
        guard abs(targetOffset - startOffset) > 0.5 else {
            renderedHorizontalOffsets[workspace.id] = targetOffset
            self.pendingAnimatedRevealWorkspaceID = nil
            stopHorizontalRevealAnimation()
            return
        }

        startHorizontalRevealAnimation(for: workspace.id, from: startOffset, to: targetOffset)
        self.pendingAnimatedRevealWorkspaceID = nil
    }

    private func startHorizontalRevealAnimation(for workspaceID: UUID, from startOffset: CGFloat, to targetOffset: CGFloat) {
        animatingWorkspaceID = workspaceID
        horizontalRevealAnimationStartOffset = startOffset
        horizontalRevealAnimationTargetOffset = targetOffset
        horizontalRevealAnimationStartedAt = Date()

        horizontalRevealAnimationTimer?.invalidate()
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.stepHorizontalRevealAnimation()
            }
        }
        horizontalRevealAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stepHorizontalRevealAnimation() {
        guard let workspaceID = animatingWorkspaceID else { return }

        let elapsed = Date().timeIntervalSince(horizontalRevealAnimationStartedAt)
        let progress = min(max(elapsed / Metrics.horizontalRevealAnimationDuration, 0), 1)
        let eased = 1 - pow(1 - progress, 3)
        let currentOffset = horizontalRevealAnimationStartOffset
            + (horizontalRevealAnimationTargetOffset - horizontalRevealAnimationStartOffset) * eased

        renderedHorizontalOffsets[workspaceID] = currentOffset
        onChange?()

        if progress >= 1 {
            stopHorizontalRevealAnimation()
        }
    }

    private func stopHorizontalRevealAnimation() {
        if let animatingWorkspaceID {
            renderedHorizontalOffsets[animatingWorkspaceID] = horizontalRevealAnimationTargetOffset
        }
        horizontalRevealAnimationTimer?.invalidate()
        horizontalRevealAnimationTimer = nil
        animatingWorkspaceID = nil
    }
}

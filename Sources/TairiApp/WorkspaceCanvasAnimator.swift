import AppKit
import Foundation

@MainActor
final class WorkspaceCanvasAnimator {
    enum OpeningTileAnimationStyle: Equatable {
        case widthExpand
        case verticalSplit
    }

    private enum Metrics {
        static let horizontalRevealAnimationDuration: TimeInterval = 0.2
        static let stripLeadingInsetAnimationDuration: TimeInterval = 0.28
        static let closingGapAnimationDuration: TimeInterval = 0.22
        static let openingTileAnimationDuration: TimeInterval = 0.2
        static let tileReorderAnimationDuration: TimeInterval = 0.33
    }

    private struct ClosingGapAnimation {
        let workspaceID: UUID
        let insertionIndex: Int
        let startWidth: CGFloat
        let targetWidth: CGFloat
        let startedAt: Date
    }

    private struct OpeningTileAnimation {
        let tileID: UUID
        let style: OpeningTileAnimationStyle
        let startedAt: Date
    }

    private struct TileReorderAnimation {
        let tileIDs: Set<UUID>
        let startFrames: [UUID: CGRect]
        let startedAt: Date
    }

    var onChange: (() -> Void)?
    var animationPolicy: AppAnimationPolicy = .defaultValue {
        didSet {
            guard animationPolicy != oldValue else { return }
            guard !animationPolicy.effectiveAnimationsEnabled else { return }
            stopHorizontalRevealAnimation()
            stopStripLeadingInsetAnimation()
            stopClosingGapAnimation()
            stopOpeningTileAnimation()
            stopTileReorderAnimation()
            onChange?()
        }
    }

    private var renderedHorizontalOffsets: [UUID: CGFloat] = [:]
    private var pendingAnimatedRevealWorkspaceID: UUID?
    private var animatingWorkspaceID: UUID?
    private var horizontalRevealAnimationStartOffset: CGFloat = 0
    private var horizontalRevealAnimationTargetOffset: CGFloat = 0
    private var horizontalRevealAnimationStartedAt = Date.distantPast
    private var horizontalRevealAnimationTimer: Timer?
    private var renderedStripLeadingInset = WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: false)
    private var stripLeadingInsetAnimationStartValue = WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: false)
    private var stripLeadingInsetAnimationTargetValue = WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: false)
    private var stripLeadingInsetAnimationStartedAt = Date.distantPast
    private var stripLeadingInsetAnimationTimer: Timer?
    private var closingGapAnimation: ClosingGapAnimation?
    private var renderedClosingGapWidth: CGFloat = 0
    private var closingGapAnimationTimer: Timer?
    private var openingTileAnimation: OpeningTileAnimation?
    private var renderedOpeningTileProgress: CGFloat = 1
    private var openingTileAnimationTimer: Timer?
    private var tileReorderAnimation: TileReorderAnimation?
    private var renderedTileReorderProgress: CGFloat = 1
    private var tileReorderAnimationTimer: Timer?

    var isHorizontalRevealAnimationActive: Bool {
        horizontalRevealAnimationTimer != nil
    }

    func pruneOffsets(workspaces: [WorkspaceStore.Workspace]) {
        renderedHorizontalOffsets = renderedHorizontalOffsets.filter { entry in
            workspaces.contains(where: { $0.id == entry.key })
        }
        if let closingGapAnimation,
            !workspaces.contains(where: { $0.id == closingGapAnimation.workspaceID })
        {
            stopClosingGapAnimation()
        }
        if let openingTileAnimation {
            let tileStillExists = workspaces.contains { workspace in
                workspace.tiles.contains(where: { $0.id == openingTileAnimation.tileID })
            }
            if !tileStillExists {
                stopOpeningTileAnimation()
            }
        }
        if let tileReorderAnimation {
            let activeTileIDs = Set(workspaces.flatMap(\.tiles).map(\.id))
            if !tileReorderAnimation.tileIDs.isSubset(of: activeTileIDs) {
                stopTileReorderAnimation()
            }
        }
    }

    func queueReveal(for tileID: UUID, animated: Bool, in workspaces: [WorkspaceStore.Workspace]) {
        guard animationPolicy.shouldAnimate(animated) else {
            pendingAnimatedRevealWorkspaceID = nil
            return
        }

        pendingAnimatedRevealWorkspaceID =
            workspaces.first(where: { workspace in
                workspace.tiles.contains(where: { $0.id == tileID })
            })?.id
    }

    func effectiveHorizontalOffset(for workspace: WorkspaceStore.Workspace) -> CGFloat {
        renderedHorizontalOffsets[workspace.id] ?? workspace.horizontalOffset
    }

    func effectiveStripLeadingInset(sidebarHidden: Bool) -> CGFloat {
        if stripLeadingInsetAnimationTimer != nil {
            return renderedStripLeadingInset
        }
        return WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: sidebarHidden)
    }

    func queueClosingGap(
        workspaceID: UUID,
        insertionIndex: Int,
        width: CGFloat,
        animated: Bool
    ) {
        guard width > 0.5 else { return }

        if !animationPolicy.shouldAnimate(animated) {
            closingGapAnimation = nil
            renderedClosingGapWidth = 0
            stopClosingGapAnimation()
            onChange?()
            return
        }

        renderedClosingGapWidth = width
        closingGapAnimation = ClosingGapAnimation(
            workspaceID: workspaceID,
            insertionIndex: insertionIndex,
            startWidth: width,
            targetWidth: 0,
            startedAt: Date()
        )

        closingGapAnimationTimer?.invalidate()
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.stepClosingGapAnimation()
            }
        }
        closingGapAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        onChange?()
    }

    func closingGapWidth(beforeTileAt insertionIndex: Int, in workspaceID: UUID) -> CGFloat {
        guard let closingGapAnimation,
            closingGapAnimation.workspaceID == workspaceID,
            closingGapAnimation.insertionIndex == insertionIndex
        else {
            return 0
        }
        return renderedClosingGapWidth
    }

    func queueOpeningTile(
        tileID: UUID,
        animated: Bool,
        style: OpeningTileAnimationStyle
    ) {
        guard animationPolicy.shouldAnimate(animated) else {
            stopOpeningTileAnimation()
            onChange?()
            return
        }

        renderedOpeningTileProgress = 0
        openingTileAnimation = OpeningTileAnimation(
            tileID: tileID,
            style: style,
            startedAt: Date()
        )

        openingTileAnimationTimer?.invalidate()
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.stepOpeningTileAnimation()
            }
        }
        openingTileAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        onChange?()
    }

    func effectiveTileWidth(_ width: CGFloat, for tileID: UUID) -> CGFloat {
        guard let progress = openingTileProgress(for: tileID, style: .widthExpand) else {
            return width
        }
        return width * progress
    }

    func openingTileProgress(
        for tileID: UUID,
        style: OpeningTileAnimationStyle
    ) -> CGFloat? {
        guard let openingTileAnimation,
            openingTileAnimation.tileID == tileID,
            openingTileAnimation.style == style
        else {
            return nil
        }
        return renderedOpeningTileProgress
    }

    func queueTileReorder(
        tileIDs: Set<UUID>,
        startFrames: [UUID: CGRect],
        animated: Bool
    ) {
        guard !tileIDs.isEmpty else {
            stopTileReorderAnimation()
            onChange?()
            return
        }

        guard animationPolicy.shouldAnimate(animated) else {
            stopTileReorderAnimation()
            onChange?()
            return
        }

        renderedTileReorderProgress = 0
        tileReorderAnimation = TileReorderAnimation(
            tileIDs: tileIDs,
            startFrames: startFrames,
            startedAt: Date()
        )

        tileReorderAnimationTimer?.invalidate()
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.stepTileReorderAnimation()
            }
        }
        tileReorderAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        onChange?()
    }

    func reorderedFrame(for tileID: UUID, targetFrame: CGRect) -> CGRect? {
        guard let tileReorderAnimation,
            let startFrame = tileReorderAnimation.startFrames[tileID]
        else {
            return nil
        }

        return CGRect(
            x: interpolatedValue(from: startFrame.minX, to: targetFrame.minX, progress: renderedTileReorderProgress),
            y: interpolatedValue(from: startFrame.minY, to: targetFrame.minY, progress: renderedTileReorderProgress),
            width: interpolatedValue(from: startFrame.width, to: targetFrame.width, progress: renderedTileReorderProgress),
            height: interpolatedValue(from: startFrame.height, to: targetFrame.height, progress: renderedTileReorderProgress)
        )
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

    func syncRenderedStripLeadingInset(sidebarHidden: Bool, animated: Bool) {
        let targetInset = WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: sidebarHidden)
        guard abs(renderedStripLeadingInset - targetInset) > 0.5 else {
            renderedStripLeadingInset = targetInset
            stopStripLeadingInsetAnimation()
            return
        }

        guard animationPolicy.shouldAnimate(animated) else {
            renderedStripLeadingInset = targetInset
            stopStripLeadingInsetAnimation()
            onChange?()
            return
        }

        startStripLeadingInsetAnimation(to: targetInset)
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
        let duration = animationPolicy.scaledDuration(Metrics.horizontalRevealAnimationDuration)
        guard duration > 0 else {
            stopHorizontalRevealAnimation()
            onChange?()
            return
        }
        let progress = min(max(elapsed / duration, 0), 1)
        let eased = 1 - pow(1 - progress, 3)
        let currentOffset =
            horizontalRevealAnimationStartOffset
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

    private func startStripLeadingInsetAnimation(to targetInset: CGFloat) {
        if stripLeadingInsetAnimationTimer != nil,
            abs(stripLeadingInsetAnimationTargetValue - targetInset) <= 0.5
        {
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
        let duration = animationPolicy.scaledDuration(Metrics.stripLeadingInsetAnimationDuration)
        guard duration > 0 else {
            stopStripLeadingInsetAnimation()
            onChange?()
            return
        }
        let progress = min(max(elapsed / duration, 0), 1)
        let eased = 1 - pow(1 - progress, 3)
        renderedStripLeadingInset =
            stripLeadingInsetAnimationStartValue
            + (stripLeadingInsetAnimationTargetValue - stripLeadingInsetAnimationStartValue) * eased
        onChange?()

        if progress >= 1 {
            stopStripLeadingInsetAnimation()
        }
    }

    private func stopStripLeadingInsetAnimation() {
        renderedStripLeadingInset = stripLeadingInsetAnimationTargetValue
        stripLeadingInsetAnimationTimer?.invalidate()
        stripLeadingInsetAnimationTimer = nil
    }

    private func stepClosingGapAnimation() {
        guard let closingGapAnimation else { return }

        let elapsed = Date().timeIntervalSince(closingGapAnimation.startedAt)
        let duration = animationPolicy.scaledDuration(Metrics.closingGapAnimationDuration)
        guard duration > 0 else {
            stopClosingGapAnimation()
            onChange?()
            return
        }
        let progress = min(max(elapsed / duration, 0), 1)
        let eased = 1 - pow(1 - progress, 3)
        renderedClosingGapWidth =
            closingGapAnimation.startWidth
            + (closingGapAnimation.targetWidth - closingGapAnimation.startWidth) * eased
        onChange?()

        if progress >= 1 {
            stopClosingGapAnimation()
        }
    }

    private func stopClosingGapAnimation() {
        renderedClosingGapWidth = 0
        closingGapAnimation = nil
        closingGapAnimationTimer?.invalidate()
        closingGapAnimationTimer = nil
    }

    private func stepOpeningTileAnimation() {
        guard let openingTileAnimation else { return }

        let elapsed = Date().timeIntervalSince(openingTileAnimation.startedAt)
        let duration = animationPolicy.scaledDuration(Metrics.openingTileAnimationDuration)
        guard duration > 0 else {
            stopOpeningTileAnimation()
            onChange?()
            return
        }
        let progress = min(max(elapsed / duration, 0), 1)
        let eased = 1 - pow(1 - progress, 3)
        renderedOpeningTileProgress = eased
        onChange?()

        if progress >= 1 {
            stopOpeningTileAnimation()
        }
    }

    private func stopOpeningTileAnimation() {
        renderedOpeningTileProgress = 1
        openingTileAnimation = nil
        openingTileAnimationTimer?.invalidate()
        openingTileAnimationTimer = nil
    }

    private func stepTileReorderAnimation() {
        guard let tileReorderAnimation else { return }

        let elapsed = Date().timeIntervalSince(tileReorderAnimation.startedAt)
        let duration = animationPolicy.scaledDuration(Metrics.tileReorderAnimationDuration)
        guard duration > 0 else {
            stopTileReorderAnimation()
            onChange?()
            return
        }

        let progress = min(max(elapsed / duration, 0), 1)
        let eased = 1 - pow(1 - progress, 3)
        renderedTileReorderProgress = eased
        onChange?()

        if progress >= 1 {
            stopTileReorderAnimation()
        }
    }

    private func stopTileReorderAnimation() {
        renderedTileReorderProgress = 1
        tileReorderAnimation = nil
        tileReorderAnimationTimer?.invalidate()
        tileReorderAnimationTimer = nil
    }

    private func interpolatedValue(from start: CGFloat, to end: CGFloat, progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }
}

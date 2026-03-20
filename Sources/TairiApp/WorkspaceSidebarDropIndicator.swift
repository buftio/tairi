import SwiftUI

struct WorkspaceSidebarDropIndicator: Equatable {
    let workspaceID: UUID
    let position: WorkspaceStore.WorkspaceDropPosition
}

struct WorkspaceSidebarDropIndicatorView: View {
    private enum Metrics {
        static let height: CGFloat = 3
        static let horizontalInset: CGFloat = 14
        static let lift: CGFloat = 1
    }

    let workspaceID: UUID
    let position: WorkspaceStore.WorkspaceDropPosition
    let theme: GhosttyAppTheme

    init(
        for workspaceID: UUID,
        position: WorkspaceStore.WorkspaceDropPosition,
        theme: GhosttyAppTheme
    ) {
        self.workspaceID = workspaceID
        self.position = position
        self.theme = theme
    }

    var body: some View {
        Capsule(style: .continuous)
            .fill(Color(nsColor: theme.accent))
            .frame(height: Metrics.height)
            .padding(.horizontal, Metrics.horizontalInset)
            .offset(y: position == .before ? -Metrics.lift : Metrics.lift)
            .shadow(
                color: Color(nsColor: theme.accent).opacity(theme.isLightTheme ? 0.28 : 0.42),
                radius: 6,
                x: 0,
                y: 0
            )
            .allowsHitTesting(false)
            .accessibilityIdentifier(
                TairiAccessibility.workspaceDropIndicator(
                    workspaceID,
                    position: position
                )
            )
    }
}

extension WorkspaceStore.WorkspaceDropPosition {
    var sidebarAlignment: Alignment {
        switch self {
        case .before:
            return .top
        case .after:
            return .bottom
        }
    }
}

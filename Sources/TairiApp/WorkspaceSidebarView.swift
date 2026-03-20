import SwiftUI

struct WorkspaceSidebarView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var interactionController: WorkspaceInteractionController
    @EnvironmentObject private var runtime: GhosttyRuntime
    @EnvironmentObject private var chromeController: WindowChromeController
    @FocusState private var focusedRenameWorkspaceID: UUID?
    @State private var renamingWorkspaceID: UUID?
    @State private var renameDraft = ""

    let theme: GhosttyAppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                SidebarVisibilityButton(theme: theme)
            }
            .padding(.top, 14)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            workspaceList

            Rectangle()
                .fill(Color(nsColor: theme.divider).opacity(0.4))
                .frame(height: 0.5)
                .padding(.horizontal, 10)

            sidebarActions
        }
        .frame(width: WindowLayoutMetrics.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(sidebarBackground)
        .clipShape(RoundedRectangle(cornerRadius: WindowLayoutMetrics.sidebarCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WindowLayoutMetrics.sidebarCornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(theme.isLightTheme ? 0.50 : 0.18),
                            Color.white.opacity(theme.isLightTheme ? 0.10 : 0.05),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: Color(nsColor: theme.sidebarShadow), radius: 30, x: 0, y: 18)
        .padding(.leading, WindowLayoutMetrics.sidebarLeadingInset)
        .padding(.top, WindowLayoutMetrics.sidebarTopInset)
        .padding(.bottom, WindowLayoutMetrics.sidebarBottomInset)
        .opacity(chromeController.isSidebarHidden ? 0 : 1)
        .offset(
            x: chromeController.isSidebarHidden
                ? -(WindowLayoutMetrics.sidebarWidth + WindowLayoutMetrics.sidebarLeadingInset + 24)
                : 0
        )
        .allowsHitTesting(!chromeController.isSidebarHidden)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: chromeController.isSidebarHidden)
        .onChange(of: chromeController.isSidebarHidden) {
            if chromeController.isSidebarHidden {
                cancelRenaming()
            }
        }
        .accessibilityIdentifier(TairiAccessibility.workspaceSidebar)
    }

    private var workspaceList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(store.workspaces) { workspace in
                        workspaceRow(for: workspace)
                            .id(workspace.id)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .onAppear {
                scrollSelectedWorkspace(in: proxy, animated: false)
            }
            .onChange(of: store.selectedWorkspaceID) {
                scrollSelectedWorkspace(in: proxy)
            }
            .accessibilityIdentifier(TairiAccessibility.workspaceList)
        }
    }

    private var sidebarActions: some View {
        HStack(spacing: 6) {
            sidebarIconButton(icon: "plus", label: "New tile", id: TairiAccessibility.newTileButton) {
                createNewTile()
            }
            sidebarIconButton(
                icon: "chevron.up",
                label: "Prev workspace",
                id: TairiAccessibility.previousWorkspaceButton
            ) {
                selectAdjacentWorkspace(offset: -1)
            }
            sidebarIconButton(
                icon: "chevron.down",
                label: "Next workspace",
                id: TairiAccessibility.nextWorkspaceButton
            ) {
                selectAdjacentWorkspace(offset: 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    private func sidebarIconButton(icon: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: WindowLayoutMetrics.rowCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(theme.isLightTheme ? 0.08 : 0.06))
                )
                .foregroundStyle(Color(nsColor: theme.secondaryText))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityIdentifier(id)
    }

    private func workspaceRow(for workspace: WorkspaceStore.Workspace) -> some View {
        let isSelected = workspace.id == store.selectedWorkspaceID

        return Group {
            if renamingWorkspaceID == workspace.id {
                workspaceRenameField(for: workspace, isSelected: isSelected)
            } else {
                workspaceRowContent(
                    titleView: AnyView(
                        Text(workspace.title)
                            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                            .lineLimit(1)
                    ),
                    workspace: workspace,
                    isSelected: isSelected
                )
                .overlay {
                    WorkspaceRowInteractionView(
                        accessibilityIdentifier: TairiAccessibility.workspaceButton(workspace.id),
                        accessibilityLabel: workspace.title,
                        onClick: {
                            selectWorkspace(workspace)
                        },
                        onRenameRequest: {
                            beginRenaming(workspace)
                        }
                    )
                }
                .contextMenu {
                    Button("Rename") {
                        beginRenaming(workspace)
                    }
                }
                .help("Double-click or force click to rename")
            }
        }
    }

    private func workspaceRenameField(for workspace: WorkspaceStore.Workspace, isSelected: Bool) -> some View {
        workspaceRowContent(
            titleView: AnyView(
                TextField("Workspace name", text: $renameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .focused($focusedRenameWorkspaceID, equals: workspace.id)
                    .onSubmit {
                        commitRenaming()
                    }
                    .onExitCommand {
                        cancelRenaming()
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            focusedRenameWorkspaceID = workspace.id
                        }
                    }
                    .accessibilityIdentifier(TairiAccessibility.workspaceRenameField(workspace.id))
            ),
            workspace: workspace,
            isSelected: isSelected
        )
    }

    private func workspaceRowContent(
        titleView: AnyView,
        workspace: WorkspaceStore.Workspace,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 8) {
            titleView
            Spacer(minLength: 4)
            Text("\(workspace.tiles.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(
                    isSelected
                        ? Color(nsColor: theme.accent)
                        : Color(nsColor: theme.secondaryText)
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: WindowLayoutMetrics.rowCornerRadius, style: .continuous)
                .fill(
                    isSelected
                        ? Color(nsColor: theme.accent).opacity(theme.isLightTheme ? 0.12 : 0.16)
                        : Color.clear
                )
        )
        .foregroundStyle(
            isSelected
                ? Color(nsColor: theme.primaryText)
                : Color(nsColor: theme.primaryText).opacity(0.75)
        )
        .contentShape(Rectangle())
    }

    private var sidebarBackground: some View {
        RoundedRectangle(cornerRadius: WindowLayoutMetrics.sidebarCornerRadius, style: .continuous)
            .fill(.clear)
            .background(
                WindowGlassBackgroundView(
                    material: .hudWindow,
                    opacity: 1.0,
                    blendingMode: .withinWindow,
                    appearanceName: .darkAqua
                )
            )
            .clipShape(
                RoundedRectangle(cornerRadius: WindowLayoutMetrics.sidebarCornerRadius, style: .continuous)
            )
    }

    private func scrollSelectedWorkspace(in proxy: ScrollViewProxy, animated: Bool = true) {
        let scroll = {
            proxy.scrollTo(store.selectedWorkspaceID, anchor: .center)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.18)) {
                scroll()
            }
        } else {
            scroll()
        }
    }

    private func selectWorkspace(_ workspace: WorkspaceStore.Workspace) {
        cancelRenaming()

        let wasSelected = workspace.id == store.selectedWorkspaceID
        interactionController.selectWorkspace(workspace.id)
        if wasSelected {
            interactionController.revealWorkspace(workspace.id)
        }
        focusSelectedTileIfNeeded()
    }

    private func beginRenaming(_ workspace: WorkspaceStore.Workspace) {
        interactionController.selectWorkspace(workspace.id)
        renameDraft = workspace.title
        renamingWorkspaceID = workspace.id
    }

    private func commitRenaming() {
        guard let renamingWorkspaceID else { return }
        store.renameWorkspace(renamingWorkspaceID, to: renameDraft)
        cancelRenaming()
    }

    private func cancelRenaming() {
        renamingWorkspaceID = nil
        focusedRenameWorkspaceID = nil
        renameDraft = ""
    }

    private func createNewTile() {
        _ = runtime.createTile(
            nextTo: store.selectedTileID,
            workingDirectory: runtime.spawnWorkingDirectory(for: store.selectedTileID),
            transition: .animatedReveal
        )
        focusSelectedTileIfNeeded()
    }

    private func selectAdjacentWorkspace(offset: Int) {
        cancelRenaming()
        interactionController.selectAdjacentWorkspace(offset: offset)
        focusSelectedTileIfNeeded()
    }

    private func focusSelectedTileIfNeeded() {
        guard let selectedTileID = store.selectedTileID else { return }
        runtime.focusSurface(tileID: selectedTileID)
    }
}

struct SidebarVisibilityButton: View {
    @EnvironmentObject private var chromeController: WindowChromeController

    let theme: GhosttyAppTheme

    var body: some View {
        Button(action: chromeController.toggleSidebarVisibility) {
            Image(systemName: chromeController.isSidebarHidden ? "sidebar.left" : "sidebar.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(nsColor: theme.primaryText).opacity(0.82))
                .frame(width: 32, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(theme.isLightTheme ? 0.16 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(theme.isLightTheme ? 0.16 : 0.08), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .help(chromeController.isSidebarHidden ? "Show sidebar" : "Hide sidebar")
        .accessibilityIdentifier(TairiAccessibility.toggleSidebarButton)
    }
}

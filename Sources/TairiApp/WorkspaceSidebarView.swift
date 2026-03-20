import AppKit
import SwiftUI

struct WorkspaceSidebarView: View {
    private enum Metrics {
        static let toggleAnimationDuration: TimeInterval = 0.28
    }

    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var interactionController: WorkspaceInteractionController
    @EnvironmentObject private var runtime: GhosttyRuntime
    @EnvironmentObject private var chromeController: WindowChromeController
    @State private var renamingWorkspaceID: UUID?
    @State private var renameDraft = ""
    @State private var renameFolderDraft: String?

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
        .offset(x: chromeController.isSidebarHidden ? -WorkspaceCanvasLayoutMetrics.visibleStripLeadingInset : 0)
        .allowsHitTesting(!chromeController.isSidebarHidden)
        .animation(.easeOut(duration: Metrics.toggleAnimationDuration), value: chromeController.isSidebarHidden)
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
                workspaceEditorRow(for: workspace, isSelected: isSelected)
            } else {
                workspaceDisplayRow(for: workspace, isSelected: isSelected)
                    .overlay {
                        WorkspaceRowInteractionView(
                            workspaceID: workspace.id,
                            accessibilityIdentifier: TairiAccessibility.workspaceButton(workspace.id),
                            accessibilityLabel: workspace.title,
                            onClick: {
                                selectWorkspace(workspace)
                            },
                            onIconClick: {
                                assignFolder(for: workspace)
                            },
                            onRenameRequest: {
                                beginRenaming(workspace)
                            },
                            onReorderRequest: { draggedWorkspaceID, position in
                                reorderWorkspace(draggedWorkspaceID, around: workspace.id, position: position)
                            }
                        )
                    }
                    .contextMenu {
                        Button("Rename") {
                            beginRenaming(workspace)
                        }

                        Button(workspace.folderPath == nil ? "Assign Folder..." : "Change Folder...") {
                            beginRenaming(workspace)
                            chooseFolderForRename()
                        }

                        if workspace.folderPath != nil {
                            Button("Clear Folder") {
                                store.setWorkspaceFolder(workspace.id, to: nil)
                            }
                        }
                    }
                    .help("Double-click, force click, or drag to rename or reorder")
            }
        }
    }

    private func workspaceDisplayRow(for workspace: WorkspaceStore.Workspace, isSelected: Bool) -> some View {
        workspaceRowShell(
            workspace: workspace,
            isSelected: isSelected,
            folderPath: workspace.folderPath
        ) {
            VStack(alignment: .leading, spacing: workspace.folderPath == nil ? 0 : 2) {
                titleText(workspace.title, isSelected: isSelected)

                if let folderLabel = folderLabel(for: workspace.folderPath) {
                    Text(folderLabel)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color(nsColor: theme.secondaryText))
                        .lineLimit(1)
                }
            }
        }
    }

    private func workspaceEditorRow(for workspace: WorkspaceStore.Workspace, isSelected: Bool) -> some View {
        workspaceRowShell(
            workspace: workspace,
            isSelected: isSelected,
            folderPath: renameFolderDraft
        ) {
            VStack(alignment: .leading, spacing: 8) {
                WorkspaceRenameField(
                    text: $renameDraft,
                    placeholder: "Workspace name",
                    isFocused: renamingWorkspaceID == workspace.id,
                    theme: theme,
                    accessibilityIdentifier: TairiAccessibility.workspaceRenameField(workspace.id),
                    onSubmit: commitRenaming,
                    onCancel: cancelRenaming
                )

                if let folderLabel = folderLabel(for: renameFolderDraft) {
                    Text(folderLabel)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color(nsColor: theme.secondaryText))
                        .lineLimit(1)
                }
            }
        }
    }

    private func workspaceRowShell<Content: View>(
        workspace: WorkspaceStore.Workspace,
        isSelected: Bool,
        folderPath: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            workspaceIconView(for: folderPath)
                .padding(.top, 1)

            content()

            Spacer(minLength: 6)

            Text("\(workspace.tiles.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(
                    isSelected
                        ? Color(nsColor: theme.accent)
                        : Color(nsColor: theme.secondaryText)
                )
                .padding(.top, 2)
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

    private func titleText(_ title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
            .lineLimit(1)
    }

    private func workspaceIconImage(for folderPath: String?) -> NSImage? {
        guard let folderPath = WorkspaceStore.normalizedAssignedFolderPath(folderPath) else {
            return nil
        }
        return TerminalHeaderIconResolver.resolveIcon(forWorkingDirectory: folderPath)
    }

    private func folderLabel(for folderPath: String?) -> String? {
        guard let folderPath = WorkspaceStore.normalizedAssignedFolderPath(folderPath) else {
            return nil
        }
        return (folderPath as NSString).abbreviatingWithTildeInPath
    }

    @ViewBuilder
    private func workspaceIconView(for folderPath: String?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white.opacity(theme.isLightTheme ? 0.08 : 0.06))

            if let icon = workspaceIconImage(for: folderPath) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .padding(0.5)
            } else {
                Image(systemName: folderPath == nil ? "rectangle.3.group" : "folder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(nsColor: theme.secondaryText))
            }
        }
        .frame(width: 16, height: 16)
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
        renameDraft = workspace.usesAutomaticTitle ? "" : workspace.title
        renameFolderDraft = workspace.folderPath
        renamingWorkspaceID = workspace.id
    }

    private func commitRenaming() {
        guard let renamingWorkspaceID else { return }
        store.renameWorkspace(renamingWorkspaceID, to: renameDraft)
        store.setWorkspaceFolder(renamingWorkspaceID, to: renameFolderDraft)
        cancelRenaming()
    }

    private func cancelRenaming() {
        renamingWorkspaceID = nil
        renameDraft = ""
        renameFolderDraft = nil
    }

    private func chooseFolderForRename() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Assign"
        panel.message = "Choose a folder for this strip."
        if let directoryURL = initialFolderPickerURL() {
            panel.directoryURL = directoryURL
        }

        if panel.runModal() == .OK {
            renameFolderDraft = panel.url?.path(percentEncoded: false)
        }
    }

    private func assignFolder(for workspace: WorkspaceStore.Workspace) {
        interactionController.selectWorkspace(workspace.id)

        if renamingWorkspaceID == workspace.id {
            chooseFolderForRename()
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = workspace.folderPath == nil ? "Assign" : "Change"
        panel.message = "Choose a folder for this strip."
        if let currentPath = WorkspaceStore.normalizedAssignedFolderPath(workspace.folderPath) {
            panel.directoryURL = URL(fileURLWithPath: currentPath, isDirectory: true)
        } else if let initialURL = initialFolderPickerURL() {
            panel.directoryURL = initialURL
        }

        if panel.runModal() == .OK {
            store.setWorkspaceFolder(workspace.id, to: panel.url?.path(percentEncoded: false))
        }
    }

    private func initialFolderPickerURL() -> URL? {
        if let renameFolderDraft = WorkspaceStore.normalizedAssignedFolderPath(renameFolderDraft) {
            return URL(fileURLWithPath: renameFolderDraft, isDirectory: true)
        }

        if let selectedTileID = store.selectedTileID,
           let tile = store.tile(selectedTileID),
           let pwd = tile.pwd,
           !pwd.isEmpty {
            return URL(fileURLWithPath: pwd, isDirectory: true)
        }

        return URL(fileURLWithPath: TerminalWorkingDirectory.defaultDirectoryForEmptyWorkspace(), isDirectory: true)
    }

    private func reorderWorkspace(
        _ draggedWorkspaceID: UUID,
        around targetWorkspaceID: UUID,
        position: WorkspaceStore.WorkspaceDropPosition
    ) {
        guard renamingWorkspaceID == nil else { return }
        store.moveWorkspace(draggedWorkspaceID, relativeTo: targetWorkspaceID, position: position)
    }

    private func createNewTile() {
        _ = runtime.createTile(
            nextTo: store.selectedTileID,
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

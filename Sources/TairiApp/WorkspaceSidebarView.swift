import AppKit
import SwiftUI

struct WorkspaceSidebarView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var interactionController: WorkspaceInteractionController
    @EnvironmentObject private var runtime: GhosttyRuntime
    @EnvironmentObject private var chromeController: WindowChromeController
    @State private var renamingWorkspaceID: UUID?
    @State private var renameDraft = ""
    @State private var renameFolderDraft: String?
    @State private var workspaceDropIndicator: WorkspaceSidebarDropIndicator?
    @State private var iconPickerWorkspaceID: UUID?

    let theme: GhosttyAppTheme

    private var sidebarVisibilityProgress: CGFloat {
        let visibleInset = WorkspaceCanvasLayoutMetrics.visibleStripLeadingInset
        guard visibleInset > 0 else { return 1 }
        return min(max(chromeController.renderedStripLeadingInset / visibleInset, 0), 1)
    }

    private var sidebarOffset: CGFloat {
        chromeController.renderedStripLeadingInset - WorkspaceCanvasLayoutMetrics.visibleStripLeadingInset
    }

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
        .opacity(sidebarVisibilityProgress)
        .offset(x: sidebarOffset)
        .allowsHitTesting(!chromeController.isSidebarHidden)
        .onChange(of: chromeController.isSidebarHidden) {
            if chromeController.isSidebarHidden {
                cancelRenaming()
            }
        }
        .sheet(
            isPresented: Binding(
                get: { iconPickerWorkspaceID != nil },
                set: { isPresented in
                    if !isPresented {
                        iconPickerWorkspaceID = nil
                    }
                }
            )
        ) {
            if let workspaceID = iconPickerWorkspaceID,
                let workspace = store.workspaces.first(where: { $0.id == workspaceID })
            {
                WorkspaceIconPickerSheet(
                    theme: theme,
                    selectedSymbolName: workspace.iconSymbolName,
                    selectedFilePath: workspace.iconFilePath,
                    onSelectSymbol: { selectedSymbolName in
                        store.setWorkspaceIconSymbol(workspaceID, to: selectedSymbolName)
                    },
                    onChooseImageFile: {
                        chooseIconFile(for: workspace)
                    },
                    onClearIcon: {
                        store.clearWorkspaceIcon(workspaceID)
                    }
                )
            } else {
                EmptyView()
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
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
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
                            onReorderHover: { targetWorkspaceID, position in
                                showWorkspaceDropIndicator(
                                    for: targetWorkspaceID,
                                    position: position
                                )
                            },
                            onReorderHoverEnd: {
                                clearWorkspaceDropIndicator()
                            },
                            onReorderRequest: { draggedWorkspaceID, position in
                                reorderWorkspace(draggedWorkspaceID, around: workspace.id, position: position)
                            }
                        )
                    }
                    .overlay(alignment: workspaceDropIndicator?.position.sidebarAlignment ?? .center) {
                        if let indicator = workspaceDropIndicator,
                            indicator.workspaceID == workspace.id
                        {
                            WorkspaceSidebarDropIndicatorView(
                                for: workspace.id,
                                position: indicator.position,
                                theme: theme
                            )
                        }
                    }
                    .contextMenu {
                        Button("Rename") {
                            beginRenaming(workspace)
                        }

                        Button(workspace.folderPath == nil ? "Assign Folder..." : "Change Folder...") {
                            beginRenaming(workspace)
                            chooseFolderForRename()
                        }

                        Button(workspace.hasCustomIcon ? "Change Icon..." : "Choose Icon...") {
                            presentIconPicker(for: workspace)
                        }

                        if workspace.folderPath != nil {
                            Button("Clear Folder") {
                                store.setWorkspaceFolder(workspace.id, to: nil)
                            }
                        }

                        if workspace.hasCustomIcon {
                            Button("Clear Icon") {
                                store.clearWorkspaceIcon(workspace.id)
                            }
                        }

                        Divider()

                        Button("Remove Strip", role: .destructive) {
                            removeWorkspace(workspace)
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
            folderPath: workspace.folderPath,
            iconSymbolName: workspace.iconSymbolName,
            iconFilePath: workspace.iconFilePath
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
            folderPath: renameFolderDraft,
            iconSymbolName: workspace.iconSymbolName,
            iconFilePath: workspace.iconFilePath
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
        iconSymbolName: String?,
        iconFilePath: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            WorkspaceSidebarStripIconView(
                theme: theme,
                folderPath: folderPath,
                iconSymbolName: iconSymbolName,
                iconFilePath: iconFilePath
            )
            .padding(.top, 1)

            content()
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

    private func folderLabel(for folderPath: String?) -> String? {
        guard let folderPath = WorkspaceStore.normalizedAssignedFolderPath(folderPath) else {
            return nil
        }
        return (folderPath as NSString).abbreviatingWithTildeInPath
    }

    private func presentIconPicker(for workspace: WorkspaceStore.Workspace) {
        interactionController.selectWorkspace(workspace.id)
        iconPickerWorkspaceID = workspace.id
    }

    private func chooseIconFile(for workspace: WorkspaceStore.Workspace) {
        interactionController.selectWorkspace(workspace.id)
        if let filePath = WorkspaceStripIconFilePicker.chooseImageFile(for: workspace, store: store) {
            store.setWorkspaceIconFilePath(workspace.id, to: filePath)
        }
    }

    private var sidebarBackground: some View {
        let backgroundShape = RoundedRectangle(
            cornerRadius: WindowLayoutMetrics.sidebarCornerRadius,
            style: .continuous
        )
        let tintColor = Color(nsColor: theme.background)
        let tintOpacity = Double(sidebarBackgroundTintOpacity)

        return Group {
            if #available(macOS 26.0, *) {
                backgroundShape
                    .fill(.clear)
                    .glassEffect(
                        .regular
                            .tint(tintColor.opacity(tintOpacity))
                            .interactive(false),
                        in: backgroundShape
                    )
            } else {
                ZStack {
                    backgroundShape
                        .fill(.ultraThinMaterial)

                    backgroundShape
                        .fill(tintColor)
                        .opacity(tintOpacity)
                }
            }
        }
    }

    private var sidebarBackgroundTintOpacity: CGFloat {
        theme.isLightTheme ? 0.41 : 0.22
    }

    private func scrollSelectedWorkspace(in proxy: ScrollViewProxy, animated: Bool = true) {
        let scroll = {
            proxy.scrollTo(store.selectedWorkspaceID, anchor: .center)
        }

        if animated {
            withAnimation(settings.animationPolicy.swiftUIAnimation(.easeInOut, duration: 0.18)) {
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
        clearWorkspaceDropIndicator()
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
        clearWorkspaceDropIndicator()
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
            !pwd.isEmpty
        {
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
        clearWorkspaceDropIndicator()
        store.moveWorkspace(draggedWorkspaceID, relativeTo: targetWorkspaceID, position: position)
    }

    private func showWorkspaceDropIndicator(
        for workspaceID: UUID,
        position: WorkspaceStore.WorkspaceDropPosition
    ) {
        guard renamingWorkspaceID == nil else { return }
        workspaceDropIndicator = WorkspaceSidebarDropIndicator(
            workspaceID: workspaceID,
            position: position
        )
    }

    private func clearWorkspaceDropIndicator() {
        workspaceDropIndicator = nil
    }

    private func removeWorkspace(_ workspace: WorkspaceStore.Workspace) {
        clearWorkspaceDropIndicator()
        if renamingWorkspaceID == workspace.id {
            cancelRenaming()
        }
        if iconPickerWorkspaceID == workspace.id {
            iconPickerWorkspaceID = nil
        }
        runtime.removeWorkspace(workspace.id)
    }

    private func focusSelectedTileIfNeeded() {
        guard let selectedTileID = store.selectedTileID else { return }
        runtime.focusSurface(tileID: selectedTileID)
    }
}

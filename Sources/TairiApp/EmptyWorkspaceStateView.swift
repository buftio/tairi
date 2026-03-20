import AppKit
import SwiftUI

struct EmptyWorkspaceStateView: View {
    private enum Metrics {
        static let brandingIconSize: CGFloat = 132
        static let brandingCornerRadius: CGFloat = 30
        static let brandingTextHeight: CGFloat = 90
        static let fadeInDuration: TimeInterval = 0.22
    }

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: WorkspaceStore

    @State private var isVisible = false
    @State private var isRenamingWorkspace = false
    @State private var renameDraft = ""

    let theme: GhosttyAppTheme
    let branding: WorkspaceEmptyStateBranding
    let createNewTile: () -> Void
    let toggleSidebar: () -> Void
    let openKeyboardShortcuts: () -> Void

    var body: some View {
        VStack(spacing: 34) {
            if let icon = branding.icon {
                brandingIcon(icon, usesWorkspaceIdentity: branding.usesWorkspaceIdentity)
            }

            brandingContent

            VStack(alignment: .leading, spacing: 14) {
                actionButton(
                    title: "Create new tile",
                    hotkey: TairiHotkeys.newTile,
                    id: TairiAccessibility.emptyWorkspaceCreateTileHint,
                    action: createNewTile
                )
                actionButton(
                    title: "Toggle sidebar",
                    hotkey: TairiHotkeys.toggleSidebar,
                    id: TairiAccessibility.emptyWorkspaceToggleSidebarHint,
                    action: toggleSidebar
                )
                actionButton(
                    title: "Keyboard shortcuts",
                    hotkey: TairiHotkeys.openKeyboardShortcuts,
                    id: TairiAccessibility.emptyWorkspaceKeyboardShortcutsHint,
                    action: openKeyboardShortcuts
                )
            }
        }
        .frame(maxWidth: 347)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            isVisible = false
            withAnimation(settings.animationPolicy.swiftUIAnimation(.easeOut, duration: Metrics.fadeInDuration)) {
                isVisible = true
            }
        }
        .onDisappear {
            isVisible = false
            cancelRenaming()
        }
        .onChange(of: store.selectedWorkspaceID) {
            cancelRenaming()
        }
        .accessibilityIdentifier(TairiAccessibility.emptyWorkspaceState)
    }

    private var brandingContent: some View {
        VStack(spacing: 8) {
            if isRenamingWorkspace {
                renameField
            } else {
                titleDisplay
            }

            if let folderPath = WorkspaceStore.normalizedAssignedFolderPath(store.selectedWorkspace.folderPath) {
                Text((folderPath as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: theme.secondaryText).opacity(0.8))
                    .lineLimit(1)
            } else {
                managementButton(
                    label: "Add folder",
                    systemImage: "folder.badge.plus",
                    accessibilityID: TairiAccessibility.emptyWorkspaceAddFolderButton,
                    action: assignFolder
                )
            }
        }
        .frame(height: Metrics.brandingTextHeight, alignment: .top)
        .padding(.top, -18)
        .padding(.bottom, -2)
    }

    private var titleDisplay: some View {
        Text(WorkspaceDisplayIdentity.emptyStateTitle(for: store.selectedWorkspace))
            .font(.system(size: 24, weight: .semibold, design: .serif))
            .foregroundStyle(Color(nsColor: theme.primaryText).opacity(0.74))
            .shadow(
                color: Color(nsColor: theme.background).opacity(theme.isLightTheme ? 0.82 : 0.92),
                radius: 2,
                x: 0,
                y: 1
            )
            .overlay {
                EmptyWorkspaceTitleInteractionView(
                    accessibilityLabel: WorkspaceDisplayIdentity.emptyStateTitle(for: store.selectedWorkspace),
                    onRenameRequest: beginRenaming
                )
            }
            .help("Double-click or force click to rename")
    }

    private var renameField: some View {
        WorkspaceRenameField(
            text: $renameDraft,
            placeholder: WorkspaceDisplayIdentity.untitledStripTitle,
            isFocused: isRenamingWorkspace,
            theme: theme,
            font: titleFont(),
            alignment: .center,
            accessibilityIdentifier: TairiAccessibility.workspaceRenameField(store.selectedWorkspaceID),
            onSubmit: commitRenaming,
            onCancel: cancelRenaming
        )
        .frame(width: 280)
        .shadow(
            color: Color(nsColor: theme.background).opacity(theme.isLightTheme ? 0.82 : 0.92),
            radius: 2,
            x: 0,
            y: 1
        )
    }

    private func brandingIcon(_ icon: NSImage, usesWorkspaceIdentity: Bool) -> some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: Metrics.brandingIconSize, height: Metrics.brandingIconSize)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Metrics.brandingCornerRadius,
                    style: .continuous
                )
            )
            .saturation(usesWorkspaceIdentity ? 1 : 0)
            .opacity(usesWorkspaceIdentity ? (theme.isLightTheme ? 0.90 : 0.96) : (theme.isLightTheme ? 0.10 : 0.14))
            .padding(.top, -12)
    }

    private func actionButton(
        title: String,
        hotkey: TairiHotkey,
        id: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 20) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(nsColor: theme.primaryText).opacity(0.7))
                    .shadow(
                        color: Color(nsColor: theme.background).opacity(theme.isLightTheme ? 0.85 : 0.95),
                        radius: 2,
                        x: 0,
                        y: 1
                    )

                Spacer(minLength: 16)

                HStack(spacing: 8) {
                    ForEach(Array(hotkey.displayTokens.enumerated()), id: \.offset) { _, token in
                        shortcutKeycap(token)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func shortcutKeycap(_ token: String) -> some View {
        Text(token)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(nsColor: theme.primaryText).opacity(0.86))
            .shadow(
                color: Color(nsColor: theme.background).opacity(theme.isLightTheme ? 0.85 : 0.95),
                radius: 2,
                x: 0,
                y: 1
            )
            .frame(minWidth: 22)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(theme.isLightTheme ? 0.22 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(theme.isLightTheme ? 0.12 : 0.08), lineWidth: 0.8)
            )
    }

    private func managementButton(
        label: String,
        systemImage: String,
        accessibilityID: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color(nsColor: theme.primaryText).opacity(0.76))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: WindowLayoutMetrics.rowCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(theme.isLightTheme ? 0.10 : 0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: WindowLayoutMetrics.rowCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(theme.isLightTheme ? 0.08 : 0.06), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID ?? "")
    }

    private func beginRenaming() {
        guard !isRenamingWorkspace else { return }
        let workspace = store.selectedWorkspace
        renameDraft = workspace.usesAutomaticTitle ? "" : workspace.title
        isRenamingWorkspace = true
    }

    private func commitRenaming() {
        store.renameWorkspace(store.selectedWorkspaceID, to: renameDraft)
        cancelRenaming()
    }

    private func cancelRenaming() {
        isRenamingWorkspace = false
        renameDraft = ""
    }

    private func assignFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = store.selectedWorkspace.folderPath == nil ? "Assign" : "Change"
        panel.message = "Choose a folder for this strip."
        if let currentPath = WorkspaceStore.normalizedAssignedFolderPath(store.selectedWorkspace.folderPath) {
            panel.directoryURL = URL(fileURLWithPath: currentPath, isDirectory: true)
        } else if let initialURL = initialFolderPickerURL() {
            panel.directoryURL = initialURL
        }

        if panel.runModal() == .OK {
            store.setWorkspaceFolder(store.selectedWorkspaceID, to: panel.url?.path(percentEncoded: false))
        }
    }

    private func initialFolderPickerURL() -> URL? {
        if let selectedTileID = store.selectedTileID,
           let tile = store.tile(selectedTileID),
           let pwd = tile.pwd,
           !pwd.isEmpty {
            return URL(fileURLWithPath: pwd, isDirectory: true)
        }

        return URL(
            fileURLWithPath: TerminalWorkingDirectory.defaultDirectoryForEmptyWorkspace(),
            isDirectory: true
        )
    }

    private func titleFont() -> NSFont {
        let baseFont = NSFont.systemFont(ofSize: 24, weight: .semibold)
        guard let descriptor = baseFont.fontDescriptor.withDesign(.serif) else {
            return baseFont
        }
        return NSFont(descriptor: descriptor, size: 24) ?? baseFont
    }
}

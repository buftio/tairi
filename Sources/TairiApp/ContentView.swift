import SwiftUI

private enum LayoutMetrics {
    static let sidebarWidth: CGFloat = 210
    static let sidebarLeadingInset: CGFloat = 11
    static let sidebarTopInset: CGFloat = 9
    static let sidebarBottomInset: CGFloat = 11
    static let sidebarCornerRadius: CGFloat = WorkspaceTileChromeMetrics.cornerRadius
    static let rowCornerRadius: CGFloat = 6  // sidebarCornerRadius - horizontal inset
}

private enum WindowTexture {
    static let paper: NSImage? = {
        guard let url = Bundle.module.url(
            forResource: "paper",
            withExtension: "png",
            subdirectory: "Textures"
        ) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()
}

struct WindowGlassBackgroundView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let opacity: CGFloat
    let blendingMode: NSVisualEffectView.BlendingMode
    let appearanceName: NSAppearance.Name?

    init(
        material: NSVisualEffectView.Material,
        opacity: CGFloat,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        appearanceName: NSAppearance.Name? = nil
    ) {
        self.material = material
        self.opacity = opacity
        self.blendingMode = blendingMode
        self.appearanceName = appearanceName
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.alphaValue = opacity
        view.appearance = appearanceName.flatMap(NSAppearance.init(named:))
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
        nsView.alphaValue = opacity
        nsView.appearance = appearanceName.flatMap(NSAppearance.init(named:))
    }
}

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var interactionController: WorkspaceInteractionController
    @EnvironmentObject private var runtime: GhosttyRuntime
    @EnvironmentObject private var chromeController: WindowChromeController
    @EnvironmentObject private var spotlightController: TileSpotlightController
    @State private var resolvedWindow: NSWindow?
    @StateObject private var trafficLightsController = WindowTrafficLightsController()
    @State private var isTrafficLightsHovering = false

    private var theme: GhosttyAppTheme { runtime.appTheme }

    var body: some View {
        ZStack(alignment: .topLeading) {
            mainPanel
            sidebar
            WindowTrafficLightsHoverRegion(isActive: chromeController.isSidebarHidden) { isHovering in
                guard isTrafficLightsHovering != isHovering else { return }
                isTrafficLightsHovering = isHovering
            }
            .frame(
                width: WindowTrafficLightsMetrics.hoverAreaWidth,
                height: WindowTrafficLightsMetrics.hoverAreaHeight
            )
            if spotlightController.isPresented {
                TileSpotlightView()
                    .zIndex(1)
            }
        }
        .accessibilityIdentifier(TairiAccessibility.appRoot)
        .background(windowBackground)
        .ignoresSafeArea()
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        .onChange(of: chromeController.isSidebarHidden) { _ in
            if !chromeController.isSidebarHidden {
                isTrafficLightsHovering = false
            }
            syncWindowChrome()
        }
        .onChange(of: isTrafficLightsHovering) { _ in
            syncWindowChrome()
        }
        .background(
            WindowAccessor { window in
                let isNewWindow = resolvedWindow !== window
                resolvedWindow = window
                trafficLightsController.attach(to: window)

                guard isNewWindow else { return }
                configure(window: window)
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
            }
        )
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App label
            Text("tairi")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(nsColor: theme.secondaryText).opacity(0.55))
                .tracking(1.5)
                .padding(.horizontal, 14)
                .padding(.top, 52)
                .padding(.bottom, 10)

            workspaceList

            // Divider
            Rectangle()
                .fill(Color(nsColor: theme.divider).opacity(0.4))
                .frame(height: 0.5)
                .padding(.horizontal, 10)

            sidebarActions
        }
        .frame(width: LayoutMetrics.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(sidebarBackground)
        .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.sidebarCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LayoutMetrics.sidebarCornerRadius, style: .continuous)
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
        .padding(.leading, LayoutMetrics.sidebarLeadingInset)
        .padding(.top, LayoutMetrics.sidebarTopInset)
        .padding(.bottom, LayoutMetrics.sidebarBottomInset)
        .opacity(chromeController.isSidebarHidden ? 0 : 1)
        .offset(x: chromeController.isSidebarHidden ? -(LayoutMetrics.sidebarWidth + LayoutMetrics.sidebarLeadingInset + 24) : 0)
        .allowsHitTesting(!chromeController.isSidebarHidden)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: chromeController.isSidebarHidden)
        .accessibilityIdentifier(TairiAccessibility.workspaceSidebar)
    }

    private var workspaceList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(store.workspaces) { workspace in
                        workspaceButton(for: workspace)
                            .id(workspace.id)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .onAppear {
                scrollSelectedWorkspace(in: proxy, animated: false)
            }
            .onChange(of: store.selectedWorkspaceID) { _ in
                scrollSelectedWorkspace(in: proxy)
            }
            .accessibilityIdentifier(TairiAccessibility.workspaceList)
        }
    }

    private var sidebarActions: some View {
        HStack(spacing: 6) {
            sidebarIconButton(icon: "plus", label: "New tile", id: TairiAccessibility.newTileButton) {
                _ = runtime.createTile(
                    nextTo: store.selectedTileID,
                    workingDirectory: runtime.spawnWorkingDirectory(for: store.selectedTileID),
                    transition: .animatedReveal
                )
                if let selectedTileID = store.selectedTileID {
                    runtime.focusSurface(tileID: selectedTileID)
                }
            }
            sidebarIconButton(icon: "chevron.up", label: "Prev workspace", id: TairiAccessibility.previousWorkspaceButton) {
                interactionController.selectAdjacentWorkspace(offset: -1)
                if let selectedTileID = store.selectedTileID {
                    runtime.focusSurface(tileID: selectedTileID)
                }
            }
            sidebarIconButton(icon: "chevron.down", label: "Next workspace", id: TairiAccessibility.nextWorkspaceButton) {
                interactionController.selectAdjacentWorkspace(offset: 1)
                if let selectedTileID = store.selectedTileID {
                    runtime.focusSurface(tileID: selectedTileID)
                }
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
                    RoundedRectangle(cornerRadius: LayoutMetrics.rowCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(theme.isLightTheme ? 0.08 : 0.06))
                )
                .foregroundStyle(Color(nsColor: theme.secondaryText))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityIdentifier(id)
    }

    private var mainPanel: some View {
        Group {
            if let error = runtime.errorMessage {
                unavailable(error)
            } else {
                WorkspaceCanvasView(
                    settings: settings,
                    store: store,
                    interactionController: interactionController,
                    runtime: runtime,
                    sidebarHidden: chromeController.isSidebarHidden
                )
            }
        }
        .overlay(alignment: .topLeading) {
            Text("Workspace \(store.selectedWorkspace.title)")
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .accessibilityIdentifier(TairiAccessibility.workspaceTitle)
                .padding(.top, 1)
                .padding(.leading, 1)
        }
        .accessibilityIdentifier(TairiAccessibility.mainPanel)
    }


    private func workspaceButton(for workspace: WorkspaceStore.Workspace) -> some View {
        let isSelected = workspace.id == store.selectedWorkspaceID
        return Button {
            let wasSelected = workspace.id == store.selectedWorkspaceID
            interactionController.selectWorkspace(workspace.id)
            if wasSelected {
                interactionController.revealWorkspace(workspace.id)
            }
            if let selectedTileID = store.selectedTileID {
                runtime.focusSurface(tileID: selectedTileID)
            }
        } label: {
            HStack(spacing: 8) {
                Text(workspace.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)
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
                RoundedRectangle(cornerRadius: LayoutMetrics.rowCornerRadius, style: .continuous)
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
        .buttonStyle(.plain)
        .accessibilityIdentifier(TairiAccessibility.workspaceButton(workspace.title))
    }

    private var windowBackground: some View {
        ZStack {
            Rectangle()
                .fill(.clear)
                .background(
                    ZStack {
                        WindowGlassBackgroundView(
                            material: .hudWindow,
                            opacity: min(settings.windowGlassOpacity * 0.82, 1)
                        )
                        WindowGlassBackgroundView(
                            material: .underWindowBackground,
                            opacity: min(settings.windowGlassOpacity * 0.55, 1)
                        )
                    }
                )

            Rectangle()
                .fill(
                    Color(nsColor: theme.background)
                        .opacity(theme.isLightTheme ? 0.40 : 0.74)
                )
            if theme.isLightTheme {
                LinearGradient(
                    colors: [
                        Color(nsColor: theme.windowBackgroundTop),
                        Color(nsColor: theme.windowBackgroundBottom),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(0.18 + (Double(settings.windowGlassOpacity) * 0.16))
                Rectangle()
                    .fill(
                        Color(nsColor: theme.foreground)
                            .opacity(0.05 + (Double(settings.windowGlassOpacity) * 0.05))
                    )
                if let paperTexture = WindowTexture.paper {
                    Rectangle()
                        .fill(
                            ImagePaint(
                                image: Image(nsImage: paperTexture),
                                scale: 0.35
                            )
                        )
                        .saturation(0)
                        .contrast(1.12)
                        .colorMultiply(Color(nsColor: theme.paperTextureTint))
                        .blendMode(.multiply)
                        .opacity(0.14 + (Double(settings.windowGlassOpacity) * 0.14))
                    Rectangle()
                        .fill(
                            ImagePaint(
                                image: Image(nsImage: paperTexture),
                                scale: 0.55
                            )
                        )
                        .saturation(0)
                        .contrast(1.08)
                        .blendMode(.overlay)
                        .opacity(0.08 + (Double(settings.windowGlassOpacity) * 0.08))
                }
            } else {
                LinearGradient(
                    colors: [
                        Color(nsColor: theme.windowBackgroundTop),
                        Color(nsColor: theme.windowBackgroundBottom),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(0.08 + (Double(settings.windowGlassOpacity) * 0.05))
                Rectangle()
                    .fill(
                        Color(nsColor: theme.foreground)
                            .opacity(0.02 + (Double(settings.windowGlassOpacity) * 0.03))
                    )

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.05),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.42)
                        )
                    )
            }
        }
        .clipped()
    }

    private var sidebarBackground: some View {
        RoundedRectangle(cornerRadius: LayoutMetrics.sidebarCornerRadius, style: .continuous)
            .fill(.clear)
            .background(
                WindowGlassBackgroundView(
                    material: .hudWindow,
                    opacity: 1.0,
                    blendingMode: .withinWindow,
                    appearanceName: .darkAqua
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.sidebarCornerRadius, style: .continuous))
    }

    private func unavailable(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ghostty runtime unavailable")
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundStyle(Color(nsColor: theme.primaryText))
            Text(error)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(nsColor: theme.secondaryText))
                .textSelection(.enabled)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier(TairiAccessibility.runtimeError)
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

    private func configure(window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentMinSize = .zero
        window.minSize = .zero
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar = nil
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }
        syncWindowChrome(for: window)
    }

    private func syncWindowChrome() {
        guard let window = resolvedWindow ?? NSApp.windows.first else { return }
        syncWindowChrome(for: window)
    }

    private func syncWindowChrome(for window: NSWindow) {
        trafficLightsController.sync(
            sidebarHidden: chromeController.isSidebarHidden,
            isHovering: isTrafficLightsHovering,
            sidebarLeadingInset: LayoutMetrics.sidebarLeadingInset,
            in: window
        )
    }
}

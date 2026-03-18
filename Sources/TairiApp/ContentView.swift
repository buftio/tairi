import SwiftUI

private enum LayoutMetrics {
    static let sidebarWidth: CGFloat = 240
    static let sidebarLeadingInset: CGFloat = 11
    static let sidebarTopInset: CGFloat = 9
    static let sidebarBottomInset: CGFloat = 11
    static let sidebarCornerRadius: CGFloat = WorkspaceTileChromeMetrics.cornerRadius
    static let controlCornerRadius: CGFloat = 8
    static let trafficLightsLeadingInset: CGFloat = 14
    static let trafficLightsTopInset: CGFloat = 20
    static let trafficLightsSpacing: CGFloat = 6
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

struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onResolve(window)
            }
        }
    }
}

struct WindowGlassBackgroundView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let opacity: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.alphaValue = opacity
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = .behindWindow
        nsView.state = .active
        nsView.alphaValue = opacity
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

    private var theme: GhosttyAppTheme { runtime.appTheme }

    var body: some View {
        ZStack(alignment: .topLeading) {
            mainPanel
            sidebar
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
            syncWindowChrome()
        }
        .background(
            WindowAccessor { window in
                let isNewWindow = resolvedWindow !== window
                resolvedWindow = window

                guard isNewWindow else { return }
                configure(window: window)
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
            }
        )
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("tairi")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(Color(nsColor: theme.primaryText))

            workspaceList
            sidebarActions
        }
        .padding(.horizontal, 11)
        .padding(.top, 38)
        .padding(.bottom, 16)
        .frame(width: LayoutMetrics.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(sidebarBackground)
        .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.sidebarCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LayoutMetrics.sidebarCornerRadius, style: .continuous)
                .stroke(Color(nsColor: theme.sidebarStroke), lineWidth: 1)
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
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(store.workspaces) { workspace in
                        workspaceButton(for: workspace)
                            .id(workspace.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 6)
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
        VStack(alignment: .leading, spacing: 10) {
            actionButton("New tile", shortcut: "cmd+n") {
                _ = runtime.createTile(
                    nextTo: store.selectedTileID,
                    workingDirectory: runtime.spawnWorkingDirectory(for: store.selectedTileID),
                    transition: .animatedReveal
                )
                if let selectedTileID = store.selectedTileID {
                    runtime.focusSurface(tileID: selectedTileID)
                }
            }
            actionButton("Prev workspace", shortcut: "opt+cmd+↑") {
                interactionController.selectAdjacentWorkspace(offset: -1)
                if let selectedTileID = store.selectedTileID {
                    runtime.focusSurface(tileID: selectedTileID)
                }
            }
            actionButton("Next workspace", shortcut: "opt+cmd+↓") {
                interactionController.selectAdjacentWorkspace(offset: 1)
                if let selectedTileID = store.selectedTileID {
                    runtime.focusSurface(tileID: selectedTileID)
                }
            }
        }
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

    private func actionButton(_ title: String, shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(nsColor: theme.primaryText))
                Spacer()
                Text(shortcut)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(nsColor: theme.secondaryText))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: LayoutMetrics.controlCornerRadius)
                    .fill(Color(nsColor: theme.actionBackground))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier(for: title))
    }

    private func workspaceButton(for workspace: WorkspaceStore.Workspace) -> some View {
        Button {
            interactionController.selectWorkspace(workspace.id)
        } label: {
            HStack {
                Text(workspace.title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Spacer()
                Text("\(workspace.tiles.count)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: LayoutMetrics.controlCornerRadius)
                    .fill(
                        Color(
                            nsColor: workspace.id == store.selectedWorkspaceID
                                ? theme.activeWorkspaceFill
                                : theme.inactiveWorkspaceFill
                        )
                    )
            )
            .foregroundStyle(
                Color(
                    nsColor: workspace.id == store.selectedWorkspaceID
                        ? theme.activeWorkspaceText
                        : theme.primaryText
                )
            )
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
        ZStack {
            RoundedRectangle(cornerRadius: LayoutMetrics.sidebarCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: LayoutMetrics.sidebarCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: theme.sidebarOverlayTop),
                            Color(nsColor: theme.sidebarOverlayBottom)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: LayoutMetrics.sidebarCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: theme.sidebarHighlight),
                            Color.clear,
                            Color(nsColor: theme.sidebarOverlayBottom)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
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

    private func accessibilityIdentifier(for title: String) -> String {
        switch title {
        case "New tile":
            TairiAccessibility.newTileButton
        case "Prev workspace":
            TairiAccessibility.previousWorkspaceButton
        case "Next workspace":
            TairiAccessibility.nextWorkspaceButton
        default:
            title
        }
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
        positionTrafficLights(in: window)
    }

    private func syncWindowChrome() {
        guard let window = resolvedWindow ?? NSApp.windows.first else { return }
        DispatchQueue.main.async {
            self.positionTrafficLights(in: window)
        }
    }

    private func positionTrafficLights(in window: NSWindow) {
        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let buttons = buttonTypes.compactMap { window.standardWindowButton($0) }
        guard let buttonContainer = buttons.first?.superview else { return }

        buttonContainer.layoutSubtreeIfNeeded()

        let startX = LayoutMetrics.sidebarLeadingInset + LayoutMetrics.trafficLightsLeadingInset
        let y = buttonContainer.bounds.height - LayoutMetrics.trafficLightsTopInset - (buttons.first?.frame.height ?? 0)

        var x = startX
        for button in buttons {
            button.setFrameOrigin(NSPoint(x: x, y: y))
            x += button.frame.width + LayoutMetrics.trafficLightsSpacing
        }

        syncTrafficLights(buttons)
    }

    private func syncTrafficLights(_ buttons: [NSButton]) {
        let shouldHide = chromeController.isSidebarHidden
        let targetAlpha: CGFloat = shouldHide ? 0 : 1
        let needsUpdate = buttons.contains { button in
            abs(button.alphaValue - targetAlpha) > 0.01 || button.isEnabled == shouldHide
        }

        guard needsUpdate else { return }

        if !shouldHide {
            for button in buttons {
                button.isEnabled = true
                if button.alphaValue < 0.99 {
                    button.alphaValue = 0
                }
            }
        } else {
            for button in buttons {
                button.isEnabled = false
            }
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for button in buttons {
                button.animator().alphaValue = targetAlpha
            }
        }
    }
}

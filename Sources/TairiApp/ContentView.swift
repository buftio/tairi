import SwiftUI

enum WindowLayoutMetrics {
    static let sidebarWidth: CGFloat = 210
    static let sidebarLeadingInset: CGFloat = 11
    static let sidebarTopInset: CGFloat = 9
    static let sidebarBottomInset: CGFloat = 11
    static let sidebarCornerRadius: CGFloat = WorkspaceTileChromeMetrics.cornerRadius
    static let rowCornerRadius: CGFloat = 6
}

private enum WindowTexture {
    static let appIcon: NSImage? = {
        if let appIcon = Bundle.main.image(forResource: "AppIcon") {
            TairiLog.write("window texture appIcon source=Bundle.main.image")
            return appIcon
        }

        guard let url = Bundle.main.resourceURL?.appendingPathComponent("AppIcon.icns") else {
            TairiLog.write("window texture appIcon source=missing resourceURL")
            return nil
        }

        guard let appIcon = NSImage(contentsOf: url) else {
            TairiLog.write("window texture appIcon source=AppIcon.icns status=load_failed path=\(url.path(percentEncoded: false))")
            return nil
        }

        TairiLog.write("window texture appIcon source=AppIcon.icns path=\(url.path(percentEncoded: false))")
        return appIcon
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
    @EnvironmentObject private var shortcutsController: KeyboardShortcutsController
    @State private var resolvedWindow: NSWindow?
    @StateObject private var trafficLightsController = WindowTrafficLightsController()
    @State private var isTrafficLightsHovering = false
    @State private var isWindowFullscreen = false

    private var theme: GhosttyAppTheme { runtime.appTheme }
    private var totalTileCount: Int { store.workspaces.reduce(0) { $0 + $1.tiles.count } }
    private var shouldShowZoomOutOverviewButton: Bool {
        runtime.errorMessage == nil
            && totalTileCount > 3
            && interactionController.canvasZoomMode != .overview
    }

    var body: some View {
        let selectedWorkspace = store.selectedWorkspace
        let isSelectedWorkspaceEmpty = selectedWorkspace.tiles.isEmpty
        let emptyWorkspaceBranding = WorkspaceDisplayIdentity.emptyStateBranding(
            for: selectedWorkspace,
            defaultIcon: WindowTexture.appIcon
        )

        ZStack(alignment: .topLeading) {
            mainPanel(
                selectedWorkspace: selectedWorkspace,
                isSelectedWorkspaceEmpty: isSelectedWorkspaceEmpty,
                emptyWorkspaceBranding: emptyWorkspaceBranding
            )
            WorkspaceSidebarView(theme: theme)
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
        .preferredColorScheme(theme.isLightTheme ? .light : .dark)
        .ignoresSafeArea()
        .onAppear {
            AppActivation.bringAppToFront()
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
            syncWindowAppearance()
        }
        .onChange(of: chromeController.isSidebarHidden) {
            if !chromeController.isSidebarHidden {
                isTrafficLightsHovering = false
            }
            syncWindowChrome()
        }
        .onChange(of: theme) {
            syncWindowAppearance()
        }
        .onChange(of: isTrafficLightsHovering) {
            syncWindowChrome()
        }
        .onChange(of: settings.animationPolicy) {
            syncWindowChrome()
        }
        .onChange(of: store.selectedWorkspaceID) {
            TairiLog.write(
                "content view selectedWorkspace changed workspace=\(store.selectedWorkspaceID.uuidString) tile=\(store.selectedTileID?.uuidString ?? "none") empty=\(isSelectedWorkspaceEmpty)"
            )
        }
        .onChange(of: store.selectedTileID) {
            TairiLog.write(
                "content view selectedTile changed workspace=\(store.selectedWorkspaceID.uuidString) tile=\(store.selectedTileID?.uuidString ?? "none") empty=\(isSelectedWorkspaceEmpty)"
            )
        }
        .onChange(of: isSelectedWorkspaceEmpty) {
            TairiLog.write(
                "content view emptyWorkspace changed workspace=\(store.selectedWorkspaceID.uuidString) tile=\(store.selectedTileID?.uuidString ?? "none") empty=\(isSelectedWorkspaceEmpty)"
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
            guard let window = notification.object as? NSWindow, window === resolvedWindow else { return }
            isWindowFullscreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
            guard let window = notification.object as? NSWindow, window === resolvedWindow else { return }
            isWindowFullscreen = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow, window === resolvedWindow else { return }
            TairiLog.write(
                "content view window didBecomeKey window=\(window.windowNumber) workspace=\(store.selectedWorkspaceID.uuidString) tile=\(store.selectedTileID?.uuidString ?? "none")"
            )
            restoreSelectedTileFocusIfNeeded(in: window)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow, window === resolvedWindow else { return }
            TairiLog.write("content view window didResignKey window=\(window.windowNumber)")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow, window === resolvedWindow else { return }
            TairiLog.write(
                "content view window willClose window=\(window.windowNumber) workspace=\(store.selectedWorkspaceID.uuidString) tile=\(store.selectedTileID?.uuidString ?? "none") empty=\(isSelectedWorkspaceEmpty)"
            )
        }
        .background(
            WindowAccessor { window in
                let isNewWindow = resolvedWindow !== window
                resolvedWindow = window
                syncWindowFullscreenState(for: window)
                trafficLightsController.attach(to: window)

                guard isNewWindow else { return }
                TairiLog.write(
                    "content view resolvedWindow window=\(window.windowNumber) workspace=\(store.selectedWorkspaceID.uuidString) tile=\(store.selectedTileID?.uuidString ?? "none")"
                )
                configure(window: window)
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
                restoreSelectedTileFocusIfNeeded(in: window)
            }
        )
    }

    private func mainPanel(
        selectedWorkspace: WorkspaceStore.Workspace,
        isSelectedWorkspaceEmpty: Bool,
        emptyWorkspaceBranding: WorkspaceEmptyStateBranding
    ) -> some View {
        Group {
            if let error = runtime.errorMessage {
                unavailable(error)
            } else {
                WorkspaceCanvasView(
                    settings: settings,
                    store: store,
                    interactionController: interactionController,
                    runtime: runtime,
                    sidebarHidden: chromeController.isSidebarHidden,
                    renderedStripLeadingInset: chromeController.renderedStripLeadingInset
                )
            }
        }
        .overlay(alignment: .topLeading) {
            Text("Workspace \(selectedWorkspace.title)")
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .accessibilityIdentifier(TairiAccessibility.workspaceTitle)
                .padding(.top, 1)
                .padding(.leading, 1)
        }
        .overlay {
            if runtime.errorMessage == nil, isSelectedWorkspaceEmpty {
                EmptyWorkspaceStateView(
                    theme: theme,
                    branding: emptyWorkspaceBranding,
                    workspaceSnapshot: selectedWorkspace,
                    selectedTileID: store.selectedTileID,
                    createNewTile: createNewTile,
                    toggleSidebar: chromeController.toggleSidebarVisibility,
                    openKeyboardShortcuts: shortcutsController.present
                )
                .padding(.horizontal, 24)
                .offset(x: chromeController.renderedStripLeadingInset / 2)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if shouldShowZoomOutOverviewButton {
                Button(action: interactionController.zoomOutCanvas) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(nsColor: theme.primaryText).opacity(0.82))
                        .frame(width: 34, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.white.opacity(theme.isLightTheme ? 0.16 : 0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.white.opacity(theme.isLightTheme ? 0.16 : 0.08), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .help("Zoom out overview (\(TairiHotkeys.zoomOutOverview.displayLabel))")
                .padding(.trailing, 18)
                .padding(.bottom, 18)
                .accessibilityIdentifier(TairiAccessibility.zoomOutOverviewButton)
            }
        }
        .accessibilityIdentifier(TairiAccessibility.mainPanel)
    }

    private var windowBackground: some View {
        let tintColor = Color(nsColor: theme.background)
        let tintOpacity = Double(settings.windowBackgroundOpacity(isLightTheme: theme.isLightTheme))
        let glassShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        return Group {
            if isWindowFullscreen {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)

                    Rectangle()
                        .fill(tintColor)
                        .opacity(tintOpacity)
                }
            } else if #available(macOS 26.0, *) {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(
                        .clear
                            .tint(tintColor.opacity(tintOpacity))
                            .interactive(false),
                        in: glassShape
                    )
            } else {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)

                    Rectangle()
                        .fill(tintColor)
                        .opacity(tintOpacity)
                }
            }
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

    private func createNewTile() {
        _ = runtime.createTile(
            nextTo: store.selectedTileID,
            transition: .animatedReveal
        )
        focusSelectedTileIfNeeded()
    }

    private func focusSelectedTileIfNeeded() {
        guard let selectedTileID = store.selectedTileID else { return }
        runtime.focusSurface(tileID: selectedTileID)
    }

    private func restoreSelectedTileFocusIfNeeded(in window: NSWindow) {
        guard runtime.errorMessage == nil else { return }
        guard !spotlightController.isPresented else { return }
        guard window.attachedSheet == nil else { return }
        guard !windowHasActiveTextInput(window) else { return }

        DispatchQueue.main.async {
            guard resolvedWindow === window else { return }
            guard window.isKeyWindow else { return }
            focusSelectedTileIfNeeded()
        }
    }

    private func windowHasActiveTextInput(_ window: NSWindow) -> Bool {
        guard let textView = window.firstResponder as? NSTextView else { return false }
        return textView.isFieldEditor || textView.isEditable
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

    private func syncWindowAppearance() {
        guard let window = resolvedWindow ?? NSApp.windows.first else { return }
        window.appearance = NSAppearance(named: theme.appearanceName)
    }

    private func syncWindowChrome(for window: NSWindow) {
        window.appearance = NSAppearance(named: theme.appearanceName)
        trafficLightsController.sync(
            sidebarHidden: chromeController.isSidebarHidden,
            isHovering: isTrafficLightsHovering,
            sidebarLeadingInset: WindowLayoutMetrics.sidebarLeadingInset,
            animationPolicy: settings.animationPolicy,
            in: window
        )
    }

    private func syncWindowFullscreenState(for window: NSWindow) {
        isWindowFullscreen = window.styleMask.contains(.fullScreen)
    }
}

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

    static let appIcon: NSImage? = {
        guard let url = Bundle.module.url(
            forResource: "AppIcon",
            withExtension: "png"
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
    private var isSelectedWorkspaceEmpty: Bool { store.selectedWorkspace.tiles.isEmpty }
    @MainActor
    private var emptyWorkspaceBranding: WorkspaceEmptyStateBranding {
        WorkspaceDisplayIdentity.emptyStateBranding(
            for: store.selectedWorkspace,
            defaultIcon: WindowTexture.appIcon
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            mainPanel
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
        .ignoresSafeArea()
        .onAppear {
            AppActivation.bringAppToFront()
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        .onChange(of: chromeController.isSidebarHidden) {
            if !chromeController.isSidebarHidden {
                isTrafficLightsHovering = false
            }
            syncWindowChrome()
        }
        .onChange(of: isTrafficLightsHovering) {
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
                    sidebarHidden: chromeController.isSidebarHidden,
                    renderedStripLeadingInset: chromeController.renderedStripLeadingInset
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
        .overlay {
            if runtime.errorMessage == nil, isSelectedWorkspaceEmpty {
                EmptyWorkspaceStateView(
                    theme: theme,
                    branding: emptyWorkspaceBranding,
                    createNewTile: createNewTile,
                    toggleSidebar: chromeController.toggleSidebarVisibility
                )
                    .padding(.horizontal, 24)
            }
        }
        .accessibilityIdentifier(TairiAccessibility.mainPanel)
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
            sidebarLeadingInset: WindowLayoutMetrics.sidebarLeadingInset,
            in: window
        )
    }
}

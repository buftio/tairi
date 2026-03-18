import AppKit
import SwiftUI

private enum TileSpotlightMetrics {
    static let panelWidth: CGFloat = 500
    static let cornerRadius: CGFloat = 22
    static let rowCornerRadius: CGFloat = 16  // panelCornerRadius - listHorizontalPad
    static let maxVisibleResults = 7
    static let rowHeight: CGFloat = 54
    static let listVerticalPad: CGFloat = 5
    static let listHorizontalPad: CGFloat = 6
}

struct TileSpotlightView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var interactionController: WorkspaceInteractionController
    @EnvironmentObject private var runtime: GhosttyRuntime
    @EnvironmentObject private var spotlightController: TileSpotlightController
    @FocusState private var isSearchFieldFocused: Bool

    private var theme: GhosttyAppTheme { runtime.appTheme }

    private var results: [TileSpotlightResult] {
        store.spotlightResults(matching: spotlightController.query)
    }

    private var isShowingRecents: Bool {
        spotlightController.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var visibleResultCount: Int {
        min(results.count, TileSpotlightMetrics.maxVisibleResults)
    }

    private var resultListHeight: CGFloat {
        CGFloat(max(visibleResultCount, 1)) * TileSpotlightMetrics.rowHeight
            + TileSpotlightMetrics.listVerticalPad * 2
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(theme.isLightTheme ? 0.10 : 0.28)
                    .ignoresSafeArea()
                    .onTapGesture {
                        spotlightController.close()
                    }

                spotlightPanel
                    .frame(width: min(TileSpotlightMetrics.panelWidth, proxy.size.width - 40))
                    .offset(y: -(min(proxy.size.height * 0.13, 88)))
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95, anchor: .center).combined(with: .opacity),
                        removal: .scale(scale: 0.98).combined(with: .opacity)
                    ))
            }
        }
        .background(
            TileSpotlightKeyMonitor(
                onMoveUp: {
                    spotlightController.moveSelection(delta: -1, within: results)
                },
                onMoveDown: {
                    spotlightController.moveSelection(delta: 1, within: results)
                },
                onConfirm: {
                    chooseSelectedResult()
                },
                onCancel: {
                    spotlightController.close()
                }
            )
        )
        .onAppear {
            spotlightController.syncSelection(with: results, preferredID: store.selectedTileID)
            TairiLog.write(
                "spotlight appear query=\(spotlightController.query.debugDescription) results=\(results.count) selected=\(spotlightController.selectedResultID?.uuidString ?? "none")"
            )
            isSearchFieldFocused = true
        }
        .onChange(of: spotlightController.query) { _ in
            spotlightController.selectedResultID = results.first?.id
            TairiLog.write(
                "spotlight query changed query=\(spotlightController.query.debugDescription) results=\(results.count) selected=\(spotlightController.selectedResultID?.uuidString ?? "none")"
            )
        }
        .onChange(of: results) { _ in
            spotlightController.syncSelection(with: results)
            TairiLog.write(
                "spotlight results updated query=\(spotlightController.query.debugDescription) results=\(results.count) selected=\(spotlightController.selectedResultID?.uuidString ?? "none")"
            )
        }
        .onDisappear {
            TairiLog.write("spotlight disappear")
            isSearchFieldFocused = false
        }
        .accessibilityIdentifier(TairiAccessibility.tileSpotlight)
    }

    // MARK: - Panel

    private var spotlightPanel: some View {
        VStack(spacing: 0) {
            searchField

            if !results.isEmpty {
                panelDivider
                resultList
            } else if !isShowingRecents {
                panelDivider
                emptyState
            }
        }
        .background(glassBackground)
        .shadow(color: .black.opacity(theme.isLightTheme ? 0.10 : 0.24), radius: 32, x: 0, y: 14)
        .onTapGesture {}
    }

    private var glassBackground: some View {
        ZStack {
            // Base material blur
            RoundedRectangle(cornerRadius: TileSpotlightMetrics.cornerRadius, style: .continuous)
                .fill(.clear)
                .background(
                    WindowGlassBackgroundView(material: .hudWindow, opacity: 1.0)
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: TileSpotlightMetrics.cornerRadius, style: .continuous)
                )

            // Top-weighted inner highlight (lens effect)
            RoundedRectangle(cornerRadius: TileSpotlightMetrics.cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(theme.isLightTheme ? 0.10 : 0.05),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.4)
                    )
                )

            // Specular border stroke
            RoundedRectangle(cornerRadius: TileSpotlightMetrics.cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(theme.isLightTheme ? 0.52 : 0.20),
                            Color.white.opacity(theme.isLightTheme ? 0.10 : 0.05),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        }
    }

    private var panelDivider: some View {
        Rectangle()
            .fill(Color(nsColor: theme.divider).opacity(0.6))
            .frame(height: 0.5)
            .padding(.horizontal, 0)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(nsColor: theme.secondaryText))

            TextField("Search tiles…", text: $spotlightController.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color(nsColor: theme.primaryText))
                .focused($isSearchFieldFocused)
                .onSubmit {
                    chooseSelectedResult()
                }
                .accessibilityIdentifier(TairiAccessibility.tileSpotlightSearchField)

            if !spotlightController.query.isEmpty {
                Button {
                    spotlightController.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(nsColor: theme.secondaryText).opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    // MARK: - Result list

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(results) { result in
                        TileSpotlightRow(
                            theme: theme,
                            result: result,
                            isSelected: result.id == spotlightController.selectedResultID,
                            onHover: {
                                spotlightController.selectedResultID = result.id
                            },
                            onChoose: {
                                choose(result)
                            }
                        )
                        .id(result.id)
                    }
                }
                .padding(.vertical, TileSpotlightMetrics.listVerticalPad)
                .padding(.horizontal, TileSpotlightMetrics.listHorizontalPad)
            }
            .frame(height: resultListHeight)
            .onChange(of: spotlightController.selectedResultID) { selectedResultID in
                guard let selectedResultID else { return }
                withAnimation(.easeInOut(duration: 0.12)) {
                    proxy.scrollTo(selectedResultID, anchor: .center)
                }
            }
        }
        .accessibilityIdentifier(TairiAccessibility.tileSpotlightResults)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        Text("No matching tiles")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color(nsColor: theme.secondaryText))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 18)
            .padding(.vertical, 22)
    }

    // MARK: - Actions

    private func chooseSelectedResult() {
        guard let result = spotlightController.selectedResult(in: results) else {
            TairiLog.write(
                "spotlight choose skipped query=\(spotlightController.query.debugDescription) reason=no-result"
            )
            return
        }
        choose(result)
    }

    private func choose(_ result: TileSpotlightResult) {
        TairiLog.write(
            "spotlight choose tile=\(result.id.uuidString) workspace=\(result.workspaceTitle) query=\(spotlightController.query.debugDescription) path=\((result.path ?? "none").debugDescription)"
        )
        spotlightController.close()
        TairiLog.write("spotlight selecting tile=\(result.id.uuidString)")
        interactionController.selectTile(result.id, transition: .animatedReveal)
        TairiLog.write("spotlight focusing tile=\(result.id.uuidString)")
        runtime.focusSurface(tileID: result.id)
        TairiLog.write("spotlight focus requested tile=\(result.id.uuidString)")
    }
}

// MARK: - Row

private struct TileSpotlightRow: View {
    let theme: GhosttyAppTheme
    let result: TileSpotlightResult
    let isSelected: Bool
    let onHover: () -> Void
    let onChoose: () -> Void
    @State private var isHovered = false

    private var accentColor: Color { Color(nsColor: theme.accent) }
    private var primaryColor: Color { Color(nsColor: theme.primaryText) }
    private var secondaryColor: Color { Color(nsColor: theme.secondaryText) }

    var body: some View {
        Button(action: onChoose) {
            HStack(spacing: 12) {
                // Terminal icon
                Image(systemName: "terminal")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(
                        isSelected ? accentColor : secondaryColor.opacity(0.75)
                    )
                    .frame(width: 22)

                // Title + path
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.tileTitle)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(primaryColor)

                    Text(result.path ?? result.folderName)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .lineLimit(1)
                        .foregroundStyle(secondaryColor.opacity(0.8))
                }

                Spacer(minLength: 8)

                // Workspace label (subtle)
                Text(result.workspaceTitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryColor.opacity(0.45))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: TileSpotlightMetrics.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(TairiAccessibility.tileSpotlightResult(result.id))
        .accessibilityLabel("Tile \(result.tileTitle) in folder \(result.folderName)")
        .onHover { hovered in
            isHovered = hovered
            if hovered {
                onHover()
            }
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: TileSpotlightMetrics.rowCornerRadius, style: .continuous)
            .fill(rowFill)
            .animation(.easeInOut(duration: 0.10), value: isSelected)
            .animation(.easeInOut(duration: 0.10), value: isHovered)
    }

    private var rowFill: Color {
        if isSelected {
            return Color(nsColor: theme.accent).opacity(theme.isLightTheme ? 0.12 : 0.16)
        }
        if isHovered {
            return Color.white.opacity(theme.isLightTheme ? 0.10 : 0.06)
        }
        return .clear
    }
}

// MARK: - Key monitor

private struct TileSpotlightKeyMonitor: NSViewRepresentable {
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.start()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onMoveUp = onMoveUp
        context.coordinator.onMoveDown = onMoveDown
        context.coordinator.onConfirm = onConfirm
        context.coordinator.onCancel = onCancel
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var onMoveUp: () -> Void = {}
        var onMoveDown: () -> Void = {}
        var onConfirm: () -> Void = {}
        var onCancel: () -> Void = {}
        private var monitor: Any?

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func stop() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            switch event.keyCode {
            case 126:
                onMoveUp()
                return nil
            case 125:
                onMoveDown()
                return nil
            case 36, 76:
                onConfirm()
                return nil
            case 53:
                onCancel()
                return nil
            default:
                return event
            }
        }
    }
}

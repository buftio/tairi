import SwiftUI

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

struct ContentView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var runtime: GhosttyRuntime

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.3)
            mainPanel
        }
        .accessibilityIdentifier(TairiAccessibility.appRoot)
        .background(Color(red: 0.94, green: 0.93, blue: 0.90))
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        .background(
            WindowAccessor { window in
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
            }
        )
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("tairi")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                Text("appkit workspace canvas over live ghostty surfaces")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(store.workspaces) { workspace in
                    Button {
                        store.selectWorkspace(workspace.id)
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
                            RoundedRectangle(cornerRadius: 10)
                                .fill(workspace.id == store.selectedWorkspaceID ? Color.black : Color.black.opacity(0.06))
                        )
                        .foregroundStyle(workspace.id == store.selectedWorkspaceID ? Color.white : Color.black)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(TairiAccessibility.workspaceButton(workspace.title))
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                actionButton("New tile", shortcut: "cmd+n") {
                    _ = store.addTerminalTile(nextTo: store.selectedTileID)
                }
                actionButton("Prev workspace", shortcut: "cmd+[") {
                    store.selectAdjacentWorkspace(offset: -1)
                }
                actionButton("Next workspace", shortcut: "cmd+]") {
                    store.selectAdjacentWorkspace(offset: 1)
                }
            }
        }
        .padding(18)
        .frame(width: 220)
        .background(Color.black.opacity(0.035))
        .accessibilityIdentifier(TairiAccessibility.workspaceSidebar)
    }

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.15)
            if let error = runtime.errorMessage {
                unavailable(error)
            } else {
                WorkspaceCanvasView(store: store, runtime: runtime)
            }
        }
        .accessibilityIdentifier(TairiAccessibility.mainPanel)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Workspace \(store.selectedWorkspace.title)")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .accessibilityIdentifier(TairiAccessibility.workspaceTitle)
                Text("tairi owns tile layout, focus, and drag resizing around live ghostty surfaces")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let selectedTile = store.selectedTile {
                Picker("Width", selection: Binding(
                    get: { WorkspaceStore.WidthPreset.closest(to: selectedTile.width) },
                    set: { store.setWidth($0, for: selectedTile.id) }
                )) {
                    ForEach(WorkspaceStore.WidthPreset.allCases, id: \.self) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                .accessibilityIdentifier(TairiAccessibility.widthPicker)
            }
        }
        .padding(18)
    }

    private func actionButton(_ title: String, shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Spacer()
                Text(shortcut)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.6)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier(for: title))
    }

    private func unavailable(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ghostty runtime unavailable")
                .font(.system(size: 20, weight: .bold, design: .serif))
            Text(error)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
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
}

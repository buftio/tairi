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
                Text("scrollable terminal workspaces")
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
                            Text("\(workspace.sessions.count)")
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
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                actionButton("New column", shortcut: "cmd+n") {
                    _ = store.addSession(nextTo: store.selectedSessionID)
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
    }

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.15)
            if let error = runtime.errorMessage {
                unavailable(error)
            } else {
                strip
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Workspace \(store.selectedWorkspace.title)")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                Text("new terminals append as columns and never resize the existing strip")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let selected = store.selectedSessionID, let session = store.session(selected) {
                Picker("Width", selection: Binding(
                    get: { session.width },
                    set: { store.setWidth($0, for: selected) }
                )) {
                    ForEach(WorkspaceStore.WidthPreset.allCases, id: \.self) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
        }
        .padding(18)
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 22) {
                    ForEach(store.selectedWorkspace.sessions) { session in
                        terminalCard(session)
                            .id(session.id)
                    }
                }
                .padding(22)
            }
            .onChange(of: store.selectedSessionID) { sessionID in
                guard let sessionID else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(sessionID, anchor: .center)
                }
            }
        }
    }

    private func terminalCard(_ session: WorkspaceStore.Session) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .lineLimit(1)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text(session.pwd ?? FileManager.default.currentDirectoryPath)
                        .lineLimit(1)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(store.selectedSessionID == session.id ? Color.green : Color.black.opacity(0.18))
                    .frame(width: 8, height: 8)
            }
            .padding(14)
            .background(Color.black.opacity(0.04))

            GhosttyTerminalView(runtime: runtime, sessionID: session.id)
                .background(Color.black)
                .frame(width: session.width.width, height: 620)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(store.selectedSessionID == session.id ? Color.black : Color.black.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 22, x: 0, y: 18)
        .onTapGesture {
            runtime.focus(sessionID: session.id)
        }
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
    }
}

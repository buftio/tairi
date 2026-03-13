import SwiftUI

@main
struct TairiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: WorkspaceStore
    @StateObject private var runtime: GhosttyRuntime

    init() {
        let store = WorkspaceStore()
        _store = StateObject(wrappedValue: store)
        _runtime = StateObject(wrappedValue: GhosttyRuntime(store: store))
    }

    var body: some Scene {
        WindowGroup("tairi") {
            ContentView()
                .environmentObject(store)
                .environmentObject(runtime)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .commands {
            CommandMenu("Workspace") {
                Button("New Tile") {
                    _ = store.addTerminalTile(nextTo: store.selectedTileID)
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Previous Tile") {
                    store.selectAdjacentTile(offset: -1)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .control])

                Button("Next Tile") {
                    store.selectAdjacentTile(offset: 1)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .control])

                Button("Previous Workspace") {
                    store.selectAdjacentWorkspace(offset: -1)
                }
                .keyboardShortcut("[", modifiers: [.command])

                Button("Next Workspace") {
                    store.selectAdjacentWorkspace(offset: 1)
                }
                .keyboardShortcut("]", modifiers: [.command])
            }
        }
    }
}

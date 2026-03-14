import SwiftUI

@main
struct TairiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: WorkspaceStore
    @StateObject private var interactionController: WorkspaceInteractionController
    @StateObject private var runtime: GhosttyRuntime

    init() {
        let store = WorkspaceStore()
        let interactionController = WorkspaceInteractionController(store: store)
        _store = StateObject(wrappedValue: store)
        _interactionController = StateObject(wrappedValue: interactionController)
        _runtime = StateObject(wrappedValue: GhosttyRuntime(store: store, interactionController: interactionController))
    }

    var body: some Scene {
        WindowGroup("tairi") {
            ContentView()
                .environmentObject(store)
                .environmentObject(interactionController)
                .environmentObject(runtime)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Workspace") {
                Button("New Tile") {
                    _ = store.addTerminalTile(nextTo: store.selectedTileID)
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Previous Tile") {
                    interactionController.selectAdjacentTile(offset: -1, transition: .animatedReveal)
                    if let selectedTileID = store.selectedTileID {
                        runtime.focusSurface(tileID: selectedTileID)
                    }
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])

                Button("Next Tile") {
                    interactionController.selectAdjacentTile(offset: 1, transition: .animatedReveal)
                    if let selectedTileID = store.selectedTileID {
                        runtime.focusSurface(tileID: selectedTileID)
                    }
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])

                Button("Previous Workspace") {
                    interactionController.selectAdjacentWorkspace(offset: -1)
                    if let selectedTileID = store.selectedTileID {
                        runtime.focusSurface(tileID: selectedTileID)
                    }
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])

                Button("Next Workspace") {
                    interactionController.selectAdjacentWorkspace(offset: 1)
                    if let selectedTileID = store.selectedTileID {
                        runtime.focusSurface(tileID: selectedTileID)
                    }
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            }
        }
    }
}

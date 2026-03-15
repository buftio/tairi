import SwiftUI

@main
struct TairiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var store: WorkspaceStore
    @StateObject private var interactionController: WorkspaceInteractionController
    @StateObject private var runtime: GhosttyRuntime
    @StateObject private var chromeController: WindowChromeController

    init() {
        TairiCrashReporter.shared.install()
        let settings = AppSettings()
        let store = WorkspaceStore()
        let interactionController = WorkspaceInteractionController(store: store)
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: store)
        _interactionController = StateObject(wrappedValue: interactionController)
        _runtime = StateObject(
            wrappedValue: GhosttyRuntime(
                store: store,
                interactionController: interactionController,
                settings: settings
            )
        )
        _chromeController = StateObject(wrappedValue: WindowChromeController())
    }

    var body: some Scene {
        WindowGroup("tairi") {
            ContentView()
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(interactionController)
                .environmentObject(runtime)
                .environmentObject(chromeController)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Workspace") {
                Button("New Tile") {
                    _ = runtime.createTile(
                        nextTo: store.selectedTileID,
                        workingDirectory: runtime.spawnWorkingDirectory(for: store.selectedTileID),
                        transition: .preserveViewport
                    )
                    if let selectedTileID = store.selectedTileID {
                        runtime.focusSurface(tileID: selectedTileID)
                    }
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

                Divider()

                Button(chromeController.isSidebarHidden ? "Show Sidebar" : "Hide Sidebar") {
                    chromeController.toggleSidebarVisibility()
                }
                .keyboardShortcut("b", modifiers: [.command, .option])
            }
        }
        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }
}

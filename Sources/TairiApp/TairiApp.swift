import AppKit
import SwiftUI

@main
struct TairiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var store: WorkspaceStore
    @StateObject private var interactionController: WorkspaceInteractionController
    @StateObject private var runtime: GhosttyRuntime
    @StateObject private var chromeController: WindowChromeController
    @StateObject private var spotlightController: TileSpotlightController

    init() {
        TairiCrashReporter.shared.install()
        let launchConfiguration = TairiLaunchConfiguration.fromProcessArguments()
        let settings = AppSettings()
        let store = WorkspaceStore(
            initialStrips: launchConfiguration.resolvedInitialStrips
        )
        let interactionController = WorkspaceInteractionController(store: store)
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: store)
        _interactionController = StateObject(wrappedValue: interactionController)
        _runtime = StateObject(
            wrappedValue: GhosttyRuntime(
                store: store,
                interactionController: interactionController,
                settings: settings,
                launchConfiguration: launchConfiguration
            )
        )
        _chromeController = StateObject(wrappedValue: WindowChromeController(settings: settings))
        _spotlightController = StateObject(wrappedValue: TileSpotlightController())
    }

    var body: some Scene {
        WindowGroup("tairi") {
            ContentView()
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(interactionController)
                .environmentObject(runtime)
                .environmentObject(chromeController)
                .environmentObject(spotlightController)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Ghostty Settings...") {
                    GhosttyConfigAccess.openSettingsFile()
                }
                .tairiKeyboardShortcut(TairiHotkeys.openGhosttySettings)

                Button("Reload Ghostty Configuration") {
                    runtime.reloadConfiguration()
                }
                .tairiKeyboardShortcut(TairiHotkeys.reloadGhosttyConfiguration)
                .disabled(runtime.errorMessage != nil)
            }

            CommandMenu("Keybindings") {
                ForEach(Array(TairiHotkeys.sections.enumerated()), id: \.element.id) { index, section in
                    if index > 0 {
                        Divider()
                    }

                    Menu(section.title) {
                        ForEach(section.entries) { entry in
                            shortcutReferenceButton(title: entry.title, hotkey: entry.hotkey)
                        }
                    }
                }
            }

            CommandMenu("Workspace") {
                Button("Search Tiles...") {
                    spotlightController.toggle(selecting: store.selectedTileID)
                }
                .tairiKeyboardShortcut(TairiHotkeys.searchTiles)

                Divider()

                Button("New Tile") {
                    _ = runtime.createTile(
                        nextTo: store.selectedTileID,
                        transition: .animatedReveal
                    )
                    if let selectedTileID = store.selectedTileID {
                        runtime.focusSurface(tileID: selectedTileID)
                    }
                }
                .tairiKeyboardShortcut(TairiHotkeys.newTile)

                Button("Split Horizontally") {
                    runtime.splitSelectedTileHorizontally()
                }
                .tairiKeyboardShortcut(TairiHotkeys.splitHorizontally)

                Button("Previous Tile") {
                    interactionController.selectAdjacentTile(offset: -1, transition: .animatedReveal)
                    if let selectedTileID = store.selectedTileID {
                        runtime.focusSurface(tileID: selectedTileID)
                    }
                }
                .tairiKeyboardShortcut(TairiHotkeys.previousTile)

                Button("Next Tile") {
                    interactionController.selectAdjacentTile(offset: 1, transition: .animatedReveal)
                    if let selectedTileID = store.selectedTileID {
                        runtime.focusSurface(tileID: selectedTileID)
                    }
                }
                .tairiKeyboardShortcut(TairiHotkeys.nextTile)

                Button("Previous Workspace") {
                    interactionController.selectAdjacentWorkspace(offset: -1)
                    if let selectedTileID = store.selectedTileID {
                        runtime.focusSurface(tileID: selectedTileID)
                    }
                }
                .tairiKeyboardShortcut(TairiHotkeys.previousWorkspace)

                Button("Next Workspace") {
                    interactionController.selectAdjacentWorkspace(offset: 1)
                    if let selectedTileID = store.selectedTileID {
                        runtime.focusSurface(tileID: selectedTileID)
                    }
                }
                .tairiKeyboardShortcut(TairiHotkeys.nextWorkspace)

                Divider()

                Button(chromeController.isSidebarHidden ? "Show Sidebar" : "Hide Sidebar") {
                    chromeController.toggleSidebarVisibility()
                }
                .tairiKeyboardShortcut(TairiHotkeys.toggleSidebar)

                Divider()

                Button("Zoom Out Overview") {
                    interactionController.zoomOutCanvas()
                }
                .tairiKeyboardShortcut(TairiHotkeys.zoomOutOverview)

                Button("Zoom In Selection") {
                    interactionController.zoomInOnSelection(transition: .animatedReveal)
                    if let selectedTileID = store.selectedTileID {
                        runtime.focusSurface(tileID: selectedTileID)
                    }
                }
                .tairiKeyboardShortcut(TairiHotkeys.zoomInSelection)
            }
        }
        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(runtime)
        }
    }

    @ViewBuilder
    private func shortcutReferenceButton(title: String, hotkey: TairiHotkey) -> some View {
        Button("\(title) (\(hotkey.displayLabel))") {}
            .disabled(true)
    }
}

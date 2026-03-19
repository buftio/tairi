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
                    openGhosttySettings()
                }
                .keyboardShortcut(",", modifiers: [.command, .option])

                Button("Reload Ghostty Configuration") {
                    runtime.reloadConfiguration()
                }
                .keyboardShortcut(",", modifiers: [.command, .shift])
                .disabled(runtime.errorMessage != nil)
            }

            CommandMenu("Workspace") {
                Button("Search Tiles...") {
                    spotlightController.toggle(selecting: store.selectedTileID)
                }
                .keyboardShortcut("k", modifiers: [.command])

                Divider()

                Button("New Tile") {
                    _ = runtime.createTile(
                        nextTo: store.selectedTileID,
                        workingDirectory: runtime.spawnWorkingDirectory(for: store.selectedTileID),
                        transition: .animatedReveal
                    )
                    if let selectedTileID = store.selectedTileID {
                        runtime.focusSurface(tileID: selectedTileID)
                    }
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Split Horizontally") {
                    runtime.splitSelectedTileHorizontally()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

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

                Divider()

                Button("Zoom Out Overview") {
                    interactionController.zoomOutCanvas()
                }
                .keyboardShortcut("-", modifiers: [.command, .option])

                Button("Zoom In Selection") {
                    interactionController.zoomInOnSelection(transition: .animatedReveal)
                    if let selectedTileID = store.selectedTileID {
                        runtime.focusSurface(tileID: selectedTileID)
                    }
                }
                .keyboardShortcut("=", modifiers: [.command, .option])
            }
        }
        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(runtime)
        }
    }

    private func openGhosttySettings() {
        let fileManager = FileManager.default
        let configURL = TairiPaths.ghosttyConfigURL
        let directoryURL = configURL.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: configURL.path) {
                try Data().write(to: configURL, options: .atomic)
            }
            NSWorkspace.shared.open(configURL)
        } catch {
            TairiLog.write("open ghostty settings failed error=\(error.localizedDescription)")
        }
    }
}

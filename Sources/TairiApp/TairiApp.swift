import AppKit
import SwiftUI

private enum LaunchWindowMetrics {
    static let defaultWidth: CGFloat = 1320
    static let defaultHeight: CGFloat = 900
}

@main
struct TairiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var store: WorkspaceStore
    @StateObject private var interactionController: WorkspaceInteractionController
    @StateObject private var runtime: GhosttyRuntime
    @StateObject private var chromeController: WindowChromeController
    @StateObject private var spotlightController: TileSpotlightController
    @StateObject private var shortcutsController = KeyboardShortcutsController()

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
        WindowGroup("Tairi") {
            ContentView()
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(interactionController)
                .environmentObject(runtime)
                .environmentObject(chromeController)
                .environmentObject(spotlightController)
                .environmentObject(shortcutsController)
                .sheet(isPresented: $shortcutsController.isPresented) {
                    KeyboardShortcutsCheatsheetView()
                        .environmentObject(shortcutsController)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(
            width: LaunchWindowMetrics.defaultWidth,
            height: LaunchWindowMetrics.defaultHeight
        )
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NSApp.sendAction(NSSelectorFromString("showSettingsWindow:"), to: nil, from: nil)
                }
                .tairiKeyboardShortcut(TairiHotkeys.openAppSettings)
            }

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
                Button("Keyboard Shortcuts...") {
                    shortcutsController.present()
                }
                .tairiKeyboardShortcut(TairiHotkeys.openKeyboardShortcuts)

                Divider()

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

                Button("New Git Tile") {
                    _ = runtime.createGitTile(
                        nextTo: store.selectedTileID,
                        transition: .animatedReveal
                    )
                }
                .tairiKeyboardShortcut(TairiHotkeys.newGitTile)

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
                    interactionController.selectAdjacentWorkspacePreservingViewport(offset: -1)
                    if let selectedTileID = store.selectedTileID {
                        runtime.focusSurface(tileID: selectedTileID)
                    }
                }
                .tairiKeyboardShortcut(TairiHotkeys.previousWorkspace)

                Button("Next Workspace") {
                    interactionController.selectAdjacentWorkspacePreservingViewport(offset: 1)
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

            CommandGroup(after: .help) {
                Button("Export Diagnostics Bundle...") {
                    TairiDiagnosticsAccess.exportBundleInteractively()
                }
            }

            CommandGroup(after: .toolbar) {
                Button(fullScreenCommandTitle) {
                    toggleFullscreen()
                }
                .tairiKeyboardShortcut(TairiHotkeys.toggleFullscreen)
            }
        }
        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(runtime)
                .preferredColorScheme(runtime.appTheme.isLightTheme ? .light : .dark)
        }
    }

    @ViewBuilder
    private func shortcutReferenceButton(title: String, hotkey: TairiHotkey) -> some View {
        Button("\(title) (\(hotkey.displayLabel))") {}
            .disabled(true)
    }

    private var fullScreenCommandTitle: String {
        let targetWindow = NSApp.keyWindow ?? NSApp.mainWindow
        let isFullscreen = targetWindow?.styleMask.contains(.fullScreen) == true
        return isFullscreen ? "Exit Full Screen" : "Enter Full Screen"
    }

    private func toggleFullscreen() {
        let targetWindow = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible)
        guard let targetWindow else { return }
        targetWindow.toggleFullScreen(nil)
    }
}

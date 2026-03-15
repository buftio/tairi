import Foundation

@MainActor
final class WindowChromeController: ObservableObject {
    @Published private(set) var isSidebarHidden: Bool

    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        isSidebarHidden = settings.sidebarHidden
    }

    func toggleSidebarVisibility() {
        isSidebarHidden.toggle()
        settings.sidebarHidden = isSidebarHidden
    }
}

import Foundation

@MainActor
final class WindowChromeController: ObservableObject {
    @Published private(set) var isSidebarHidden = false

    func toggleSidebarVisibility() {
        isSidebarHidden.toggle()
    }
}

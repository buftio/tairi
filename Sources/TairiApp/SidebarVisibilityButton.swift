import SwiftUI

struct SidebarVisibilityButton: View {
    @EnvironmentObject private var chromeController: WindowChromeController

    let theme: GhosttyAppTheme

    var body: some View {
        Button(action: chromeController.toggleSidebarVisibility) {
            Image(systemName: chromeController.isSidebarHidden ? "sidebar.left" : "sidebar.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(nsColor: theme.primaryText).opacity(0.82))
                .frame(width: 32, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(theme.isLightTheme ? 0.16 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(theme.isLightTheme ? 0.16 : 0.08), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .help(chromeController.isSidebarHidden ? "Show sidebar" : "Hide sidebar")
        .accessibilityIdentifier(TairiAccessibility.toggleSidebarButton)
    }
}

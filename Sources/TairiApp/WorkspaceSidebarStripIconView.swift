import SwiftUI

struct WorkspaceSidebarStripIconView: View {
    let theme: GhosttyAppTheme
    let folderPath: String?
    let iconSymbolName: String?
    let iconFilePath: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white.opacity(theme.isLightTheme ? 0.08 : 0.06))

            if let icon = WorkspaceDisplayIdentity.icon(
                forFolderPath: folderPath,
                iconSymbolName: iconSymbolName,
                iconFilePath: iconFilePath
            ) {
                iconContent(icon)
            } else {
                Image(systemName: folderPath == nil ? "macwindow" : "folder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(nsColor: theme.secondaryText))
            }
        }
        .frame(width: 16, height: 16)
    }

    @ViewBuilder
    private func iconContent(_ icon: WorkspaceDisplayIcon) -> some View {
        switch icon {
        case let .image(image):
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .padding(0.5)
        case let .symbol(symbolName):
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(nsColor: theme.primaryText).opacity(0.78))
        }
    }
}

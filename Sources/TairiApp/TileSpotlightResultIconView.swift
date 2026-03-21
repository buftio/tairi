import SwiftUI

struct TileSpotlightResultIconView: View {
    let theme: GhosttyAppTheme
    let result: TileSpotlightResult
    let isSelected: Bool

    private var accentColor: Color { Color(nsColor: theme.accent) }
    private var secondaryColor: Color { Color(nsColor: theme.secondaryText) }

    var body: some View {
        Group {
            if let icon = WorkspaceDisplayIdentity.spotlightIcon(
                forTileWorkingDirectory: result.tileWorkingDirectory,
                workspaceFolderPath: result.workspaceFolderPath,
                workspaceIconSymbolName: result.workspaceIconSymbolName,
                workspaceIconFilePath: result.workspaceIconFilePath
            ) {
                iconContent(icon)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? accentColor : secondaryColor.opacity(0.75))
            }
        }
        .frame(width: 22, height: 22)
    }

    @ViewBuilder
    private func iconContent(_ icon: WorkspaceDisplayIcon) -> some View {
        switch icon {
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(1)
        case .symbol(let symbolName):
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? accentColor : secondaryColor.opacity(0.75))
        }
    }
}

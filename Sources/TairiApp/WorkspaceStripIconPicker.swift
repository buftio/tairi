import AppKit
import SwiftUI

enum WorkspaceStripIconCatalog {
    static let symbolNames = [
        "terminal",
        "folder",
        "briefcase",
        "doc.text",
        "book.closed",
        "bookmark",
        "tray.full",
        "archivebox",
        "shippingbox",
        "hammer",
        "wrench.and.screwdriver",
        "paintpalette",
        "pencil.and.ruler",
        "sparkles",
        "bolt",
        "globe",
        "network",
        "cpu",
        "server.rack",
        "puzzlepiece.extension",
        "graduationcap",
        "music.note",
        "camera",
        "gamecontroller",
        "heart",
        "flame",
        "leaf",
        "moon.stars",
    ]

    static func isSymbolAvailable(_ symbolName: String) -> Bool {
        NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil
    }

    static var availableSymbolNames: [String] {
        symbolNames.filter(isSymbolAvailable)
    }
}

struct WorkspaceIconPickerSheet: View {
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    @Environment(\.dismiss) private var dismiss

    let theme: GhosttyAppTheme
    let selectedSymbolName: String?
    let selectedFilePath: String?
    let onSelectSymbol: (String) -> Void
    let onChooseImageFile: () -> Void
    let onClearIcon: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Strip Icon")
                    .font(.system(size: 18, weight: .semibold))

                Text("Choose a custom icon for this strip.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color(nsColor: theme.secondaryText))
            }

            HStack(spacing: 12) {
                Button("Choose Image File...") {
                    dismiss()
                    onChooseImageFile()
                }

                if let selectedFilePath {
                    Text(URL(fileURLWithPath: selectedFilePath, isDirectory: false).lastPathComponent)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color(nsColor: theme.secondaryText))
                        .lineLimit(1)
                }
            }

            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(WorkspaceStripIconCatalog.availableSymbolNames, id: \.self) { symbolName in
                        iconButton(for: symbolName)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 292)

            HStack {
                Button("Use Folder Icon") {
                    onClearIcon()
                    dismiss()
                }
                .disabled(selectedSymbolName == nil && selectedFilePath == nil)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func iconButton(for symbolName: String) -> some View {
        let isSelected = symbolName == selectedSymbolName && selectedFilePath == nil

        return Button {
            onSelectSymbol(symbolName)
            dismiss()
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            isSelected
                                ? Color(nsColor: theme.accent).opacity(theme.isLightTheme ? 0.18 : 0.24)
                                : Color.white.opacity(theme.isLightTheme ? 0.08 : 0.05)
                        )

                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isSelected
                                ? Color(nsColor: theme.accent).opacity(theme.isLightTheme ? 0.62 : 0.78)
                                : Color.white.opacity(theme.isLightTheme ? 0.10 : 0.06),
                            lineWidth: 1
                        )

                    Image(systemName: symbolName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(
                            isSelected
                                ? Color(nsColor: theme.accent)
                                : Color(nsColor: theme.primaryText).opacity(0.82)
                        )
                }
                .frame(height: 62)

                Text(iconLabel(for: symbolName))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(nsColor: theme.secondaryText))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .help(iconLabel(for: symbolName))
    }

    private func iconLabel(for symbolName: String) -> String {
        symbolName
            .replacingOccurrences(of: ".", with: " ")
            .capitalized
    }
}

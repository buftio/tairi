import SwiftUI

struct GitTileView: View {
    private enum Metrics {
        static let horizontalPadding: CGFloat = 10
        static let verticalPadding: CGFloat = 10
        static let sectionSpacing: CGFloat = 8
        static let rowHeight: CGFloat = 20
    }

    @ObservedObject var model: GitTileViewModel

    let theme: GhosttyAppTheme
    let selectTile: () -> Void

    private var backgroundColor: Color { Color(nsColor: theme.background) }
    private var primaryTextColor: Color { Color(nsColor: theme.primaryText) }
    private var secondaryTextColor: Color { Color(nsColor: theme.secondaryText) }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 430
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 8 : Metrics.sectionSpacing) {
                    content(compact: compact)
                }
                .padding(.horizontal, Metrics.horizontalPadding)
                .padding(.vertical, Metrics.verticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .background(backgroundColor)
        }
    }

    @ViewBuilder
    private func content(compact: Bool) -> some View {
        switch model.state {
        case .loading:
            stateMessage(
                title: "Loading repo state",
                detail: "Reading git status and stack details.",
                compact: compact
            )
        case .noFolder:
            stateMessage(
                title: "No strip folder yet",
                detail: "Assign a folder to this strip and the git tile will follow it automatically.",
                compact: compact
            )
        case .notRepository(let folderPath):
            stateMessage(
                title: "No git repo here",
                detail: (folderPath as NSString).abbreviatingWithTildeInPath,
                compact: compact
            )
        case .failed(let message):
            stateMessage(
                title: "Couldn’t refresh this repo",
                detail: message,
                compact: compact
            )
        case .ready(let snapshot):
            VStack(alignment: .leading, spacing: compact ? 8 : Metrics.sectionSpacing) {
                summaryRow(snapshot, compact: compact)
                if shouldShowStack(snapshot) {
                    stackSection(snapshot, compact: compact)
                }
                changesSection(snapshot, compact: compact)
            }
        }
    }

    private func summaryRow(_ snapshot: GitTileSnapshot, compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(changeSummary(snapshot))
                .font(.system(size: compact ? 10 : 11, weight: .medium, design: .monospaced))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: refresh) {
                Image(systemName: model.isRefreshing ? "arrow.trianglehead.2.clockwise.rotate.90" : "arrow.clockwise")
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(primaryTextColor.opacity(0.88))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(theme.isLightTheme ? 0.16 : 0.06))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func stackSection(_ snapshot: GitTileSnapshot, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if snapshot.stackNeedsAttention {
                Text(snapshot.stackHeadline)
                    .font(.system(size: compact ? 9 : 10, weight: .semibold))
                    .foregroundStyle(warningColor)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                ForEach(Array(displayedStackLines(snapshot, compact: compact).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: compact ? 10 : 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(primaryTextColor.opacity(0.88))
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
            .padding(compact ? 8 : 10)
            .background(sectionBackground(compact: compact))
        }
    }

    private func changesSection(_ snapshot: GitTileSnapshot, compact: Bool) -> some View {
        if snapshot.treeRows.isEmpty {
            return AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    Text("Working tree is clean")
                        .font(.system(size: compact ? 12 : 13, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                    Text("This tile will keep polling for updates.")
                        .font(.system(size: compact ? 10 : 11, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                }
                .padding(compact ? 10 : 12)
                .background(sectionBackground(compact: compact))
            )
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 2) {
                ForEach(snapshot.treeRows) { row in
                    treeRow(row, compact: compact)
                }
            }
            .padding(.vertical, compact ? 6 : 8)
            .padding(.horizontal, compact ? 6 : 8)
            .background(sectionBackground(compact: compact))
        )
    }

    private func treeRow(_ row: GitTileTreeRow, compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Color.clear
                .frame(width: CGFloat(row.depth) * (compact ? 12 : 16), height: 1)

            Image(systemName: row.kind == .folder ? "chevron.down" : "doc.text")
                .font(.system(size: row.kind == .folder ? (compact ? 8 : 9) : (compact ? 10 : 11), weight: .semibold))
                .foregroundStyle(row.kind == .folder ? secondaryTextColor.opacity(0.8) : secondaryTextColor.opacity(0.6))
                .frame(width: 12)

            rowText(row)

            Spacer(minLength: 0)
        }
        .frame(minHeight: compact ? 18 : Metrics.rowHeight)
        .contentShape(Rectangle())
    }

    private func rowText(_ row: GitTileTreeRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title)
                .font(.system(size: 12, weight: row.kind == .folder ? .semibold : .medium))
                .foregroundStyle(primaryTextColor.opacity(row.kind == .folder ? 0.86 : 0.96))
                .lineLimit(1)
            if let secondaryText = row.secondaryText {
                Text(secondaryText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
            }
        }
    }

    private func stateMessage(title: String, detail: String, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .foregroundStyle(primaryTextColor)
            Text(detail)
                .font(.system(size: compact ? 10 : 11, weight: .medium))
                .foregroundStyle(secondaryTextColor)
                .textSelection(.enabled)
        }
        .padding(compact ? 10 : 12)
        .background(sectionBackground(compact: compact))
    }

    private func sectionBackground(compact: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(theme.isLightTheme ? (compact ? 0.06 : 0.08) : (compact ? 0.03 : 0.04)))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(theme.isLightTheme ? 0.08 : 0.05), lineWidth: 0.8)
            )
    }

    private func displayedStackLines(_ snapshot: GitTileSnapshot, compact: Bool) -> [String] {
        let limit = compact ? 4 : 8
        return Array(snapshot.stackLines.prefix(limit))
    }

    private var warningColor: Color {
        Color(nsColor: .systemOrange)
    }

    private func changeSummary(_ snapshot: GitTileSnapshot) -> String {
        let parts = [
            "\(snapshot.treeRows.filter { $0.kind == .file }.count) changes",
            snapshot.stagedCount > 0 ? "staged \(snapshot.stagedCount)" : nil,
            snapshot.unstagedCount > 0 ? "modified \(snapshot.unstagedCount)" : nil,
            snapshot.untrackedCount > 0 ? "new \(snapshot.untrackedCount)" : nil,
        ]
        return parts.compactMap { $0 }.joined(separator: "  ")
    }

    private func refresh() {
        selectTile()
        model.refreshNow()
    }

    private func shouldShowStack(_ snapshot: GitTileSnapshot) -> Bool {
        snapshot.graphiteEnabled || snapshot.stackNeedsAttention || snapshot.stackLines.count > 1
    }
}

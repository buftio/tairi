import Foundation

struct TileSpotlightResult: Identifiable, Equatable {
    let id: UUID
    let workspaceID: UUID
    let workspaceTitle: String
    let tileTitle: String
    let folderName: String
    let path: String?
    let score: Int
    let isCurrentWorkspace: Bool
    let isSelectedTile: Bool
    let createdAt: Date
    let lastVisitedAt: Date
}

enum TileSpotlightSearch {
    static func results(
        in workspaces: [WorkspaceStore.Workspace],
        query: String,
        selectedWorkspaceID: UUID,
        selectedTileID: UUID?,
        limit: Int = 12
    ) -> [TileSpotlightResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldBoostCurrentSelection = !trimmedQuery.isEmpty

        return
            workspaces
            .flatMap { workspace in
                workspace.tiles.map { tile -> TileSpotlightResult? in
                    let folderName = folderName(for: tile.pwd)
                    let path = normalizedPath(tile.pwd)
                    let matchScore = score(
                        query: trimmedQuery,
                        title: tile.title,
                        folderName: folderName,
                        path: path
                    )
                    guard let matchScore else {
                        return nil
                    }

                    let isCurrentWorkspace = workspace.id == selectedWorkspaceID
                    let isSelectedTile = tile.id == selectedTileID
                    let totalScore =
                        matchScore
                        + (shouldBoostCurrentSelection && isSelectedTile ? 220 : 0)
                        + (shouldBoostCurrentSelection && isCurrentWorkspace ? 60 : 0)

                    return TileSpotlightResult(
                        id: tile.id,
                        workspaceID: workspace.id,
                        workspaceTitle: workspace.title,
                        tileTitle: tile.title,
                        folderName: folderName,
                        path: path,
                        score: totalScore,
                        isCurrentWorkspace: isCurrentWorkspace,
                        isSelectedTile: isSelectedTile,
                        createdAt: tile.createdAt,
                        lastVisitedAt: tile.lastVisitedAt
                    )
                }
            }
            .compactMap { $0 }
            .sorted(by: compareResults)
            .prefix(limit)
            .map { $0 }
    }

    private static func compareResults(_ lhs: TileSpotlightResult, _ rhs: TileSpotlightResult) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }

        if lhs.isSelectedTile != rhs.isSelectedTile {
            return lhs.isSelectedTile
        }

        if lhs.isCurrentWorkspace != rhs.isCurrentWorkspace {
            return lhs.isCurrentWorkspace
        }

        if lhs.lastVisitedAt != rhs.lastVisitedAt {
            return lhs.lastVisitedAt > rhs.lastVisitedAt
        }

        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }

        if lhs.workspaceTitle != rhs.workspaceTitle {
            return lhs.workspaceTitle < rhs.workspaceTitle
        }

        return lhs.tileTitle.localizedCaseInsensitiveCompare(rhs.tileTitle) == .orderedAscending
    }

    private static func score(
        query: String,
        title: String,
        folderName: String,
        path: String?
    ) -> Int? {
        let tokens = queryTokens(from: query)
        guard !tokens.isEmpty else { return 0 }

        let fields: [(value: String, weight: Int)] = [
            (title, 5),
            (folderName, 4),
            (path ?? "", 2),
        ]

        var total = 0
        for token in tokens {
            let bestFieldScore =
                fields
                .compactMap { fieldScore(token, in: $0.value, weight: $0.weight) }
                .max()
            guard let bestFieldScore else {
                return nil
            }
            total += bestFieldScore
        }

        return total
    }

    private static func fieldScore(_ token: String, in rawValue: String, weight: Int) -> Int? {
        let value = normalize(rawValue)
        guard !value.isEmpty else { return nil }

        if value == token {
            return (1_500 * weight) - max(value.count - token.count, 0)
        }

        if value.hasPrefix(token) {
            return (1_200 * weight) - max(value.count - token.count, 0)
        }

        if let range = value.range(of: token) {
            let distance = value.distance(from: value.startIndex, to: range.lowerBound)
            return (900 * weight) - distance
        }

        return subsequenceScore(token, in: value, weight: weight)
    }

    private static func subsequenceScore(_ token: String, in value: String, weight: Int) -> Int? {
        guard !token.isEmpty else { return 0 }

        var searchIndex = value.startIndex
        var previousOffset: Int?
        var score = 0

        for character in token {
            guard let matchedIndex = value[searchIndex...].firstIndex(of: character) else {
                return nil
            }

            let offset = value.distance(from: value.startIndex, to: matchedIndex)
            score += 10

            if let previousOffset {
                let gap = offset - previousOffset - 1
                score += gap == 0 ? 20 : max(8 - gap, 1)
            } else if offset == 0 {
                score += 16
            }

            if isBoundaryMatch(at: matchedIndex, in: value) {
                score += 12
            }

            previousOffset = offset
            searchIndex = value.index(after: matchedIndex)
        }

        let slackPenalty = max(value.count - token.count, 0)
        return (220 * weight) + score - slackPenalty
    }

    private static func isBoundaryMatch(at index: String.Index, in value: String) -> Bool {
        guard index != value.startIndex else {
            return true
        }

        let previousIndex = value.index(before: index)
        let previousCharacter = value[previousIndex]
        return previousCharacter == "/"
            || previousCharacter == "-"
            || previousCharacter == "_"
            || previousCharacter == " "
            || previousCharacter == "."
    }

    private static func queryTokens(from query: String) -> [String] {
        normalize(query)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private static func folderName(for path: String?) -> String {
        guard let path = normalizedPath(path) else {
            return "Home"
        }

        let lastComponent = URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
        return lastComponent.isEmpty ? path : lastComponent
    }

    private static func normalizedPath(_ path: String?) -> String? {
        guard let path, !path.isEmpty else {
            return nil
        }

        return path
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

extension WorkspaceStore {
    func spotlightResults(matching query: String, limit: Int = 12) -> [TileSpotlightResult] {
        TileSpotlightSearch.results(
            in: workspaces,
            query: query,
            selectedWorkspaceID: selectedWorkspaceID,
            selectedTileID: selectedTileID,
            limit: limit
        )
    }
}

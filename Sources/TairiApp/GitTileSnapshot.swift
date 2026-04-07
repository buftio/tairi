import Foundation

struct GitTileStatusBadge: Equatable {
    enum Tone: Equatable {
        case staged
        case modified
        case untracked
        case deleted
        case renamed
        case added
    }

    let label: String
    let tone: Tone
}

struct GitTileTreeRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case folder
        case file
    }

    let id: String
    let depth: Int
    let kind: Kind
    let title: String
    let relativePath: String
    let secondaryText: String?
    let badges: [GitTileStatusBadge]
    let copyText: String?
}

struct GitTileSnapshot: Equatable {
    let repoRootPath: String
    let repoName: String
    let workspaceFolderPath: String
    let branchName: String
    let upstreamName: String?
    let aheadCount: Int
    let behindCount: Int
    let stagedCount: Int
    let unstagedCount: Int
    let untrackedCount: Int
    let treeRows: [GitTileTreeRow]
    let stackLines: [String]
    let stackHeadline: String
    let stackNeedsAttention: Bool
    let graphiteEnabled: Bool
    let lastUpdatedAt: Date
}

enum GitTileState: Equatable {
    case loading
    case noFolder
    case notRepository(folderPath: String)
    case ready(GitTileSnapshot)
    case failed(message: String)
}

private struct GitTileBranchState: Equatable {
    let branchName: String
    let upstreamName: String?
    let aheadCount: Int
    let behindCount: Int
}

private struct GitTileChangeEntry: Equatable {
    let path: String
    let originalPath: String?
    let badges: [GitTileStatusBadge]
    let staged: Bool
    let unstaged: Bool
    let untracked: Bool
}

private struct GitTileStatusSnapshot: Equatable {
    let branchState: GitTileBranchState
    let entries: [GitTileChangeEntry]
    let stagedCount: Int
    let unstagedCount: Int
    let untrackedCount: Int
}

private struct GitTileStackSnapshot: Equatable {
    let lines: [String]
    let headline: String
    let needsAttention: Bool
    let graphiteEnabled: Bool
}

private struct GitTileGraphiteRepoConfig: Decodable {
    let trunk: String?
}

enum GitTileSnapshotLoader {
    static func load(for workspaceFolderPath: String?) async -> GitTileState {
        guard let workspaceFolderPath = normalizedPath(workspaceFolderPath) else {
            return .noFolder
        }

        let repoRootResult = await GitTileCommandRunner.run(
            "git",
            arguments: ["--no-optional-locks", "rev-parse", "--show-toplevel"],
            currentDirectoryPath: workspaceFolderPath
        )
        guard repoRootResult.exitCode == 0 else {
            return .notRepository(folderPath: workspaceFolderPath)
        }

        let repoRootPath = repoRootResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repoRootPath.isEmpty else {
            return .notRepository(folderPath: workspaceFolderPath)
        }

        let statusResult = await GitTileCommandRunner.run(
            "git",
            arguments: ["--no-optional-locks", "status", "--porcelain=v1", "--branch"],
            currentDirectoryPath: workspaceFolderPath
        )
        guard statusResult.exitCode == 0 else {
            return .failed(message: combinedMessage(stdout: statusResult.stdout, stderr: statusResult.stderr))
        }

        let statusSnapshot = parseStatusOutput(statusResult.stdout)
        let trunkBranch = graphiteTrunkBranch(repoRootPath: repoRootPath)
        let stackSnapshot = await loadStackSnapshot(
            repoRootPath: repoRootPath,
            currentBranch: statusSnapshot.branchState.branchName,
            trunkBranch: trunkBranch
        )

        return .ready(
            GitTileSnapshot(
                repoRootPath: repoRootPath,
                repoName: URL(fileURLWithPath: repoRootPath, isDirectory: true).lastPathComponent,
                workspaceFolderPath: workspaceFolderPath,
                branchName: statusSnapshot.branchState.branchName,
                upstreamName: statusSnapshot.branchState.upstreamName,
                aheadCount: statusSnapshot.branchState.aheadCount,
                behindCount: statusSnapshot.branchState.behindCount,
                stagedCount: statusSnapshot.stagedCount,
                unstagedCount: statusSnapshot.unstagedCount,
                untrackedCount: statusSnapshot.untrackedCount,
                treeRows: makeTreeRows(from: statusSnapshot.entries),
                stackLines: stackSnapshot.lines,
                stackHeadline: stackSnapshot.headline,
                stackNeedsAttention: stackSnapshot.needsAttention,
                graphiteEnabled: stackSnapshot.graphiteEnabled,
                lastUpdatedAt: Date()
            )
        )
    }

    private static func normalizedPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed, isDirectory: true)
            .standardizedFileURL
            .path(percentEncoded: false)
    }

    private static func combinedMessage(stdout: String, stderr: String) -> String {
        let output = [stderr, stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        return output ?? "Command failed"
    }

    private static func parseStatusOutput(_ output: String) -> GitTileStatusSnapshot {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let branchState = parseBranchState(from: lines.first)
        var entries: [GitTileChangeEntry] = []
        var stagedCount = 0
        var unstagedCount = 0
        var untrackedCount = 0

        for line in lines.dropFirst() {
            guard line.count >= 3 else { continue }
            let x = character(in: line, offset: 0)
            let y = character(in: line, offset: 1)
            guard let x, let y else { continue }

            let rawPath = String(line.dropFirst(3))
            let pathComponents = rawPath.components(separatedBy: " -> ")
            let path = pathComponents.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? rawPath
            let originalPath =
                pathComponents.count > 1
                ? pathComponents.first?.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil

            let isUntracked = x == "?" && y == "?"
            let isStaged = x != " " && x != "?"
            let isUnstaged = y != " " && y != "?"

            if isStaged { stagedCount += 1 }
            if isUnstaged { unstagedCount += 1 }
            if isUntracked { untrackedCount += 1 }

            entries.append(
                GitTileChangeEntry(
                    path: path,
                    originalPath: originalPath,
                    badges: badges(forIndexStatus: x, worktreeStatus: y),
                    staged: isStaged,
                    unstaged: isUnstaged,
                    untracked: isUntracked
                )
            )
        }

        return GitTileStatusSnapshot(
            branchState: branchState,
            entries: entries.sorted { lhs, rhs in
                lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
            },
            stagedCount: stagedCount,
            unstagedCount: unstagedCount,
            untrackedCount: untrackedCount
        )
    }

    private static func parseBranchState(from line: String?) -> GitTileBranchState {
        guard let line, line.hasPrefix("## ") else {
            return GitTileBranchState(branchName: "HEAD", upstreamName: nil, aheadCount: 0, behindCount: 0)
        }

        let body = String(line.dropFirst(3))
        let headline = body.components(separatedBy: " [").first ?? body
        let relation = body.contains(" [") ? String(body.split(separator: "[", maxSplits: 1)[1].dropLast()) : ""
        let branchPart = headline.components(separatedBy: "...").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "HEAD"
        let upstreamPart =
            headline.contains("...")
            ? headline.components(separatedBy: "...").dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil

        var aheadCount = 0
        var behindCount = 0
        for item in relation.split(separator: ",") {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("ahead ") {
                aheadCount = Int(trimmed.dropFirst("ahead ".count)) ?? 0
            } else if trimmed.hasPrefix("behind ") {
                behindCount = Int(trimmed.dropFirst("behind ".count)) ?? 0
            }
        }

        return GitTileBranchState(
            branchName: branchPart,
            upstreamName: upstreamPart,
            aheadCount: aheadCount,
            behindCount: behindCount
        )
    }

    private static func badges(forIndexStatus x: Character, worktreeStatus y: Character) -> [GitTileStatusBadge] {
        if x == "?" && y == "?" {
            return [GitTileStatusBadge(label: "U", tone: .untracked)]
        }

        var badges: [GitTileStatusBadge] = []
        if let badge = badge(for: x, isWorktree: false) {
            badges.append(badge)
        }
        if let badge = badge(for: y, isWorktree: true) {
            badges.append(badge)
        }
        return badges
    }

    private static func badge(for status: Character, isWorktree: Bool) -> GitTileStatusBadge? {
        switch status {
        case "M":
            return GitTileStatusBadge(label: "M", tone: isWorktree ? .modified : .staged)
        case "A":
            return GitTileStatusBadge(label: "A", tone: .added)
        case "D":
            return GitTileStatusBadge(label: "D", tone: .deleted)
        case "R":
            return GitTileStatusBadge(label: "R", tone: .renamed)
        case "C":
            return GitTileStatusBadge(label: "C", tone: .staged)
        case "T":
            return GitTileStatusBadge(label: "T", tone: .modified)
        case "U":
            return GitTileStatusBadge(label: "U", tone: .modified)
        case " ":
            return nil
        case "?":
            return GitTileStatusBadge(label: "U", tone: .untracked)
        default:
            return GitTileStatusBadge(label: String(status), tone: isWorktree ? .modified : .staged)
        }
    }

    private static func makeTreeRows(from entries: [GitTileChangeEntry]) -> [GitTileTreeRow] {
        var rows: [GitTileTreeRow] = []
        var visibleFolders = Set<String>()

        for entry in entries {
            let components = entry.path.split(separator: "/").map(String.init)
            guard let filename = components.last else { continue }
            if components.count > 1 {
                var prefixComponents: [String] = []
                for (index, component) in components.dropLast().enumerated() {
                    prefixComponents.append(component)
                    let prefixPath = prefixComponents.joined(separator: "/")
                    if visibleFolders.insert(prefixPath).inserted {
                        rows.append(
                            GitTileTreeRow(
                                id: "folder:\(prefixPath)",
                                depth: index,
                                kind: .folder,
                                title: component,
                                relativePath: prefixPath,
                                secondaryText: nil,
                                badges: [],
                                copyText: nil
                            )
                        )
                    }
                }
            }

            rows.append(
                GitTileTreeRow(
                    id: "file:\(entry.path)",
                    depth: max(components.count - 1, 0),
                    kind: .file,
                    title: filename,
                    relativePath: entry.path,
                    secondaryText: entry.originalPath.map { "from \($0)" },
                    badges: entry.badges,
                    copyText: entry.path
                )
            )
        }

        return rows
    }

    private static func graphiteTrunkBranch(repoRootPath: String) -> String? {
        let configPath = URL(fileURLWithPath: repoRootPath, isDirectory: true)
            .appendingPathComponent(".git/.graphite_repo_config", isDirectory: false)
            .path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: configPath),
            let data = FileManager.default.contents(atPath: configPath),
            let config = try? JSONDecoder().decode(GitTileGraphiteRepoConfig.self, from: data)
        else {
            return nil
        }
        return config.trunk
    }

    private static func loadStackSnapshot(
        repoRootPath: String,
        currentBranch: String,
        trunkBranch: String?
    ) async -> GitTileStackSnapshot {
        if trunkBranch != nil {
            let graphiteResult = await GitTileCommandRunner.run(
                "gt",
                arguments: ["log", "short", "--no-interactive", "--stack"],
                currentDirectoryPath: repoRootPath
            )
            if graphiteResult.exitCode == 0 {
                let lines = sanitizedLines(from: graphiteResult.stdout)
                let trunkHeadline = await stackHeadline(
                    repoRootPath: repoRootPath,
                    currentBranch: currentBranch,
                    trunkBranch: trunkBranch
                )
                return GitTileStackSnapshot(
                    lines: lines.isEmpty ? ["No tracked stack output"] : lines,
                    headline: trunkHeadline,
                    needsAttention: trunkHeadline.localizedCaseInsensitiveContains("ahead"),
                    graphiteEnabled: true
                )
            }

            let fallbackHeadline = await stackHeadline(
                repoRootPath: repoRootPath,
                currentBranch: currentBranch,
                trunkBranch: trunkBranch
            )
            return GitTileStackSnapshot(
                lines: [combinedMessage(stdout: graphiteResult.stdout, stderr: graphiteResult.stderr)],
                headline: fallbackHeadline,
                needsAttention: false,
                graphiteEnabled: true
            )
        }

        let fallbackResult = await GitTileCommandRunner.run(
            "git",
            arguments: [
                "--no-optional-locks",
                "for-each-ref",
                "--sort=-committerdate",
                "--format=%(if)%(HEAD)%(then)* %(else)  %(end)%(refname:short)",
                "refs/heads",
            ],
            currentDirectoryPath: repoRootPath
        )
        let lines = sanitizedLines(from: fallbackResult.stdout)
        return GitTileStackSnapshot(
            lines: Array(lines.prefix(8)),
            headline: "Graphite not initialized",
            needsAttention: false,
            graphiteEnabled: false
        )
    }

    private static func stackHeadline(
        repoRootPath: String,
        currentBranch: String,
        trunkBranch: String?
    ) async -> String {
        guard let trunkBranch, currentBranch != trunkBranch else {
            return trunkBranch == nil ? "Tracking local branches" : "On trunk"
        }

        let divergenceResult = await GitTileCommandRunner.run(
            "git",
            arguments: ["--no-optional-locks", "rev-list", "--left-right", "--count", "\(currentBranch)...\(trunkBranch)"],
            currentDirectoryPath: repoRootPath
        )
        guard divergenceResult.exitCode == 0 else {
            return "Stack updated from Graphite"
        }

        let counts = divergenceResult.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Int($0) }
        guard counts.count == 2 else {
            return "Stack updated from Graphite"
        }

        let trunkAheadCount = counts[1]
        if trunkAheadCount > 0 {
            return "\(trunkBranch) is ahead by \(trunkAheadCount)"
        }

        return "Stack updated from Graphite"
    }

    private static func sanitizedLines(from output: String) -> [String] {
        output
            .split(separator: "\n")
            .map { line in
                strippedANSIEscapeCodes(from: String(line))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private static func strippedANSIEscapeCodes(from value: String) -> String {
        value.replacingOccurrences(
            of: #"\u{001B}\[[0-9;]*[A-Za-z]"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func character(in value: String, offset: Int) -> Character? {
        guard offset >= 0, offset < value.count else { return nil }
        return value[value.index(value.startIndex, offsetBy: offset)]
    }
}

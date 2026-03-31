import Foundation

enum TerminalTitleDisplay {
    static func displayTitle(for rawTitle: String, path: String? = nil) -> String {
        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return "shell"
        }

        if let workingDirectoryTitle = workingDirectoryTitle(for: trimmedTitle, path: path) {
            return workingDirectoryTitle
        }

        return trimmedTitle
    }

    static func abbreviatedPath(_ path: String?) -> String? {
        guard let path, !path.isEmpty else {
            return nil
        }

        return normalizePathLikeTitle(NSString(string: path).abbreviatingWithTildeInPath)
    }

    static func displayPath(forTitle rawTitle: String, path: String?) -> String? {
        guard let abbreviatedPath = abbreviatedPath(path) else {
            return nil
        }

        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if workingDirectoryTitle(for: trimmedTitle, path: path) != nil {
            return nil
        }

        return abbreviatedPath
    }

    private static func workingDirectoryTitle(for trimmedTitle: String, path: String?) -> String? {
        guard let rawPathLikeTitle = pathLikeTitle(from: trimmedTitle) else {
            return nil
        }

        if let path, title(rawPathLikeTitle, matchesWorkingDirectory: path) {
            return abbreviatedPath(path) ?? normalizePathLikeTitle(rawPathLikeTitle)
        }

        return normalizePathLikeTitle(rawPathLikeTitle)
    }

    private static func pathLikeTitle(from trimmedTitle: String) -> String? {
        if isPathLike(trimmedTitle) {
            return trimmedTitle
        }

        guard
            let separatorIndex = trimmedTitle.firstIndex(of: ":"),
            trimmedTitle[..<separatorIndex].contains("@")
        else {
            return nil
        }

        let suffix = String(trimmedTitle[trimmedTitle.index(after: separatorIndex)...])
        return isPathLike(suffix) ? suffix : nil
    }

    private static func isPathLike(_ value: String) -> Bool {
        value.hasPrefix("/")
            || value.hasPrefix("~/")
            || value == "~"
            || value.hasPrefix("…/")
    }

    private static func title(_ title: String, matchesWorkingDirectory path: String) -> Bool {
        let normalizedTitle = normalizePathLikeTitle(title)
        let normalizedAbsolutePath = normalizePathLikeTitle(path)

        if normalizedTitle == normalizedAbsolutePath {
            return true
        }

        if let abbreviatedPath = abbreviatedPath(path), normalizedTitle == abbreviatedPath {
            return true
        }

        guard normalizedTitle.hasPrefix("…/") else {
            return false
        }

        let suffix = String(normalizedTitle.dropFirst(2))
        guard !suffix.isEmpty else {
            return false
        }

        return normalizedAbsolutePath.hasSuffix("/\(suffix)")
            || abbreviatedPath(path)?.hasSuffix("/\(suffix)") == true
    }

    private static func normalizePathLikeTitle(_ value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return trimmedValue
        }

        let tildeNormalizedValue =
            if trimmedValue.hasPrefix("/") {
                NSString(string: trimmedValue).abbreviatingWithTildeInPath
            } else {
                trimmedValue
            }

        guard tildeNormalizedValue.count > 1 else {
            return tildeNormalizedValue
        }

        if tildeNormalizedValue == "/" || tildeNormalizedValue == "~" {
            return tildeNormalizedValue
        }

        return tildeNormalizedValue.hasSuffix("/")
            ? String(tildeNormalizedValue.dropLast())
            : tildeNormalizedValue
    }
}

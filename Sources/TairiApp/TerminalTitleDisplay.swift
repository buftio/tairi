import Foundation

enum TerminalTitleDisplay {
    static func displayTitle(for rawTitle: String) -> String {
        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return "shell"
        }
        return trimmedTitle
    }

    static func abbreviatedPath(_ path: String?) -> String? {
        guard let path, !path.isEmpty else {
            return nil
        }

        return NSString(string: path).abbreviatingWithTildeInPath
    }

    static func displayPath(forTitle rawTitle: String, path: String?) -> String? {
        guard let abbreviatedPath = abbreviatedPath(path) else {
            return nil
        }

        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle == abbreviatedPath || trimmedTitle == path {
            return nil
        }

        return abbreviatedPath
    }
}

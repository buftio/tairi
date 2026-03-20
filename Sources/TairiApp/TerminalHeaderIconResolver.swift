import AppKit
import Foundation

enum TerminalHeaderIconResolver {
    private static let frontendIconCandidates = [
        "public/favicon.ico",
        "public/favicon.png",
        "public/favicon-96x96.png",
        "public/favicon.svg",
        "public/apple-touch-icon.png",
        "public/apple-touch-icon-precomposed.png",
        "public/icon.png",
        "public/icon.svg",
        "public/logo192.png",
        "public/logo512.png",
        "app/favicon.ico",
        "app/favicon.svg",
        "app/icon.png",
        "app/icon.svg",
        "app/apple-icon.png",
        "src/app/favicon.ico",
        "src/app/favicon-96x96.png",
        "src/app/favicon.svg",
        "src/app/icon.png",
        "src/app/icon.svg",
        "src/app/apple-icon.png",
        "static/favicon.ico",
        "static/favicon.png",
        "static/favicon.svg",
        "static/apple-touch-icon.png",
        "static/icon.png",
        "static/icon.svg",
        "static/logo.png",
        "static/logo.svg",
        "app/static/favicon.ico",
        "app/static/favicon.png",
        "app/static/favicon.svg",
        "app/static/icon.png",
        "app/static/icon.svg",
        "app/static/logo.png",
        "app/static/logo.svg",
        "app/assets/images/favicon.ico",
        "app/assets/images/favicon.png",
        "app/assets/images/favicon.svg",
        "app/assets/images/icon.png",
        "app/assets/images/icon.svg",
        "app/assets/images/logo.png",
        "app/assets/images/logo.svg",
        "src/assets/icon.png",
        "src/assets/icon.svg",
        "src/assets/logo.png",
        "src/assets/logo.svg",
        "src/assets/images/icon.png",
        "src/assets/images/icon.svg",
        "src/assets/images/logo.png",
        "src/assets/images/logo.svg",
        "favicon.ico",
        "favicon.png",
        "favicon-96x96.png",
        "favicon.svg",
        "Assets/AppIcon.png",
        "Assets/Icon.png",
        "Assets/icon.png",
        "Resources/AppIcon.png",
        "Resources/Icon.png",
        "Resources/icon.png",
        "build/appicon.png",
        "build/icon.png",
        "src-tauri/icons/icon.png",
        "src-tauri/icons/128x128.png",
        "src-tauri/icons/128x128@2x.png",
        "src-tauri/icons/Square310x310Logo.png",
        "src-tauri/icons/Square44x44Logo.png"
    ]

    private static let iconSourceFiles = [
        "index.html",
        "public/index.html",
        "app/routes/__root.tsx",
        "src/routes/__root.tsx",
        "app/root.tsx",
        "src/root.tsx",
        "src/index.html"
    ]

    private static let projectRootMarkers = [
        "package.json",
        ".git",
        "Package.swift",
        "pyproject.toml",
        "requirements.txt",
        "setup.py",
        "setup.cfg",
        "Pipfile",
        "poetry.lock",
        "manage.py",
        "go.mod",
        "go.work",
        "Cargo.toml",
        "Cargo.lock",
        "Gemfile",
        "Gemfile.lock",
        "pnpm-lock.yaml",
        "package-lock.json",
        "yarn.lock",
        "bun.lock",
        "bun.lockb",
        "next.config.js",
        "next.config.ts",
        "vite.config.js",
        "vite.config.ts",
        "astro.config.mjs",
        "astro.config.ts",
        "svelte.config.js",
        "svelte.config.ts",
        "angular.json"
    ]

    private static let linkIconHTMLRegex = try! NSRegularExpression(
        pattern: #"<link\b(?=[^>]*\brel=["'](?:icon|shortcut icon)["'])(?=[^>]*\bhref=["']([^"'?]+))[^>]*>"#,
        options: [.caseInsensitive]
    )

    private static let linkIconObjectRegex = try! NSRegularExpression(
        pattern: #"(?=[^}]*\brel\s*:\s*["'](?:icon|shortcut icon)["'])(?=[^}]*\bhref\s*:\s*["']([^"'?]+))[^}]*"#,
        options: [.caseInsensitive]
    )

    static func resolveIcon(forWorkingDirectory pwd: String?) -> NSImage? {
        if let iconURL = resolvedProjectIconURL(forWorkingDirectory: pwd),
           let assetIcon = NSImage(contentsOf: iconURL) {
            return assetIcon
        }
        return directoryIcon(for: pwd)
    }

    static func resolvedProjectIconURL(forWorkingDirectory pwd: String?) -> URL? {
        guard let startURL = workingDirectoryURL(for: pwd) else {
            return nil
        }

        for directoryURL in candidateProjectDirectories(startingAt: startURL) {
            if let iconURL = directProjectIconURL(in: directoryURL) {
                return iconURL
            }

            if let iconURL = sourceDeclaredProjectIconURL(in: directoryURL) {
                return iconURL
            }
        }

        return nil
    }

    private static func directoryIcon(for pwd: String?) -> NSImage? {
        guard let directoryURL = workingDirectoryURL(for: pwd) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: directoryURL.path(percentEncoded: false))
    }

    private static func workingDirectoryURL(for pwd: String?) -> URL? {
        let rawPath = pwd?.isEmpty == false
            ? pwd!
            : TerminalWorkingDirectory.defaultDirectoryForEmptyWorkspace()
        let url = URL(fileURLWithPath: rawPath, isDirectory: true).standardizedFileURL
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    private static func candidateProjectDirectories(startingAt startURL: URL) -> [URL] {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path(percentEncoded: false)
        var directories: [URL] = []
        var currentURL = startURL

        for depth in 0..<6 {
            directories.append(currentURL)
            if containsProjectRootMarker(at: currentURL) {
                break
            }

            let parentURL = currentURL.deletingLastPathComponent().standardizedFileURL
            let currentPath = currentURL.path(percentEncoded: false)
            let parentPath = parentURL.path(percentEncoded: false)
            if parentPath == currentPath || parentPath == homePath || depth == 5 {
                if parentPath != currentPath && parentPath != homePath {
                    directories.append(parentURL)
                }
                break
            }
            currentURL = parentURL
        }

        return directories
    }

    private static func containsProjectRootMarker(at directoryURL: URL) -> Bool {
        for marker in projectRootMarkers {
            let markerURL = directoryURL.appendingPathComponent(marker, isDirectory: false)
            if FileManager.default.fileExists(atPath: markerURL.path(percentEncoded: false)) {
                return true
            }
        }
        return false
    }

    private static func directProjectIconURL(in directoryURL: URL) -> URL? {
        for relativePath in frontendIconCandidates {
            let iconURL = directoryURL.appendingPathComponent(relativePath, isDirectory: false)
            if FileManager.default.fileExists(atPath: iconURL.path(percentEncoded: false)) {
                return iconURL
            }
        }
        return nil
    }

    private static func sourceDeclaredProjectIconURL(in directoryURL: URL) -> URL? {
        for relativePath in iconSourceFiles {
            let sourceURL = directoryURL.appendingPathComponent(relativePath, isDirectory: false)
            guard let source = try? String(contentsOf: sourceURL, encoding: .utf8),
                  let href = extractIconHref(from: source)
            else {
                continue
            }

            for candidateURL in resolveIconHref(projectDirectoryURL: directoryURL, href: href) {
                guard isPathWithinProject(projectDirectoryURL: directoryURL, candidateURL: candidateURL),
                      FileManager.default.fileExists(atPath: candidateURL.path(percentEncoded: false))
                else {
                    continue
                }
                return candidateURL
            }
        }

        return nil
    }

    private static func extractIconHref(from source: String) -> String? {
        firstCapture(in: source, using: linkIconHTMLRegex) ?? firstCapture(in: source, using: linkIconObjectRegex)
    }

    private static func firstCapture(in source: String, using regex: NSRegularExpression) -> String? {
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: source)
        else {
            return nil
        }
        return String(source[captureRange])
    }

    private static func resolveIconHref(projectDirectoryURL: URL, href: String) -> [URL] {
        let cleanHref = href
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? href
        let trimmedHref = cleanHref.trimmingCharacters(in: .whitespacesAndNewlines)
        let relativePath = trimmedHref.hasPrefix("/") ? String(trimmedHref.dropFirst()) : trimmedHref
        let publicDirectoryURL = projectDirectoryURL.appendingPathComponent("public", isDirectory: true)

        return [
            URL(fileURLWithPath: relativePath, relativeTo: publicDirectoryURL).standardizedFileURL,
            URL(fileURLWithPath: relativePath, relativeTo: projectDirectoryURL).standardizedFileURL
        ]
    }

    private static func isPathWithinProject(projectDirectoryURL: URL, candidateURL: URL) -> Bool {
        let rawProjectPath = projectDirectoryURL.standardizedFileURL
            .resolvingSymlinksInPath()
            .path(percentEncoded: false)
        let projectPath = rawProjectPath.hasSuffix("/") && rawProjectPath.count > 1
            ? String(rawProjectPath.dropLast())
            : rawProjectPath
        let candidatePath = candidateURL.standardizedFileURL
            .resolvingSymlinksInPath()
            .path(percentEncoded: false)

        if candidatePath == projectPath {
            return true
        }

        return candidatePath.hasPrefix(projectPath + "/")
    }
}

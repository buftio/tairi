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
        "favicon.ico",
        "favicon.png",
        "favicon-96x96.png",
        "favicon.svg"
    ]

    private static let projectRootMarkers = [
        "package.json",
        ".git",
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

    static func resolveIcon(forWorkingDirectory pwd: String?) -> NSImage? {
        if let assetIcon = frontendProjectIcon(forWorkingDirectory: pwd) {
            return assetIcon
        }
        return directoryIcon(for: pwd)
    }

    private static func frontendProjectIcon(forWorkingDirectory pwd: String?) -> NSImage? {
        guard let startURL = workingDirectoryURL(for: pwd) else {
            return nil
        }

        for directoryURL in candidateProjectDirectories(startingAt: startURL) {
            for relativePath in frontendIconCandidates {
                let iconURL = directoryURL.appendingPathComponent(relativePath, isDirectory: false)
                guard FileManager.default.fileExists(atPath: iconURL.path(percentEncoded: false)),
                      let image = NSImage(contentsOf: iconURL)
                else {
                    continue
                }
                return image
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
}

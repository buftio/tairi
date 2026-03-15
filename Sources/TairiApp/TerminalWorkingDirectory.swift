import Foundation

enum TerminalWorkingDirectory {
    static var homeDirectoryPath: String {
        FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
    }

    static func defaultInitialLaunchDirectory() -> String {
        defaultInitialLaunchDirectory(
            currentDirectoryPath: FileManager.default.currentDirectoryPath,
            homeDirectoryPath: homeDirectoryPath
        )
    }

    static func defaultInitialLaunchDirectory(
        currentDirectoryPath: String,
        homeDirectoryPath: String
    ) -> String {
        isRepositoryWorkingDirectory(currentDirectoryPath) ? currentDirectoryPath : homeDirectoryPath
    }

    static func defaultDirectoryForEmptyWorkspace() -> String {
        homeDirectoryPath
    }

    private static func isRepositoryWorkingDirectory(_ path: String) -> Bool {
        let root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let packagePath = root.appendingPathComponent("Package.swift").path(percentEncoded: false)
        let sourcesPath = root.appendingPathComponent("Sources/TairiApp").path(percentEncoded: false)

        return FileManager.default.fileExists(atPath: packagePath)
            && FileManager.default.fileExists(atPath: sourcesPath)
    }
}

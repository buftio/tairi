import Foundation

struct PersistedWorkspaceStrip: Codable, Equatable {
    var customTitle: String?
    var folderPath: String?
}

final class WorkspaceSidebarPersistence {
    static let stripsKey = "workspaceSidebarPersistentStrips"

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadStrips() -> [PersistedWorkspaceStrip] {
        guard let data = userDefaults.data(forKey: Self.stripsKey) else {
            return []
        }

        do {
            return try decoder.decode([PersistedWorkspaceStrip].self, from: data)
        } catch {
            TairiLog.write("workspace sidebar persistence load failed: \(error.localizedDescription)")
            userDefaults.removeObject(forKey: Self.stripsKey)
            return []
        }
    }

    func saveStrips(_ strips: [PersistedWorkspaceStrip]) {
        guard !strips.isEmpty else {
            userDefaults.removeObject(forKey: Self.stripsKey)
            return
        }

        do {
            let data = try encoder.encode(strips)
            userDefaults.set(data, forKey: Self.stripsKey)
        } catch {
            TairiLog.write("workspace sidebar persistence save failed: \(error.localizedDescription)")
        }
    }
}

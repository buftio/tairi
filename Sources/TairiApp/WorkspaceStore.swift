import Foundation

@MainActor
final class WorkspaceStore: ObservableObject {
    enum WidthPreset: String, CaseIterable, Codable {
        case narrow
        case standard
        case wide

        var width: CGFloat {
            switch self {
            case .narrow: 560
            case .standard: 760
            case .wide: 980
            }
        }

        var label: String {
            switch self {
            case .narrow: "Narrow"
            case .standard: "Standard"
            case .wide: "Wide"
            }
        }
    }

    struct Session: Identifiable, Equatable {
        let id: UUID
        var title: String
        var pwd: String?
        var width: WidthPreset
        var createdAt: Date

        init(id: UUID = UUID(), title: String = "shell", pwd: String? = nil, width: WidthPreset = .standard) {
            self.id = id
            self.title = title
            self.pwd = pwd
            self.width = width
            self.createdAt = .now
        }
    }

    struct Workspace: Identifiable, Equatable {
        let id: UUID
        var title: String
        var sessions: [Session]

        init(id: UUID = UUID(), title: String, sessions: [Session] = []) {
            self.id = id
            self.title = title
            self.sessions = sessions
        }
    }

    @Published private(set) var workspaces: [Workspace]
    @Published var selectedWorkspaceID: UUID
    @Published var selectedSessionID: UUID?

    init() {
        let first = Workspace(title: "01")
        let second = Workspace(title: "02")
        self.workspaces = [first, second]
        self.selectedWorkspaceID = first.id
        let session = addSession()
        self.selectedSessionID = session.id
    }

    var selectedWorkspace: Workspace {
        workspaces.first(where: { $0.id == selectedWorkspaceID }) ?? workspaces[0]
    }

    func sessions(in workspaceID: UUID) -> [Session] {
        workspaces.first(where: { $0.id == workspaceID })?.sessions ?? []
    }

    @discardableResult
    func addSession(nextTo sessionID: UUID? = nil) -> Session {
        let session = Session()
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }) else {
            return session
        }

        if let sessionID,
           let index = workspaces[workspaceIndex].sessions.firstIndex(where: { $0.id == sessionID }) {
            workspaces[workspaceIndex].sessions.insert(session, at: index + 1)
        } else {
            workspaces[workspaceIndex].sessions.append(session)
        }

        selectedSessionID = session.id
        normalize()
        return session
    }

    func selectWorkspace(_ workspaceID: UUID) {
        guard workspaces.contains(where: { $0.id == workspaceID }) else { return }
        selectedWorkspaceID = workspaceID
        selectedSessionID = sessions(in: workspaceID).first?.id
        normalize()
    }

    func selectSession(_ sessionID: UUID) {
        selectedSessionID = sessionID
        if let workspace = workspaceContaining(sessionID) {
            selectedWorkspaceID = workspace.id
        }
    }

    func selectAdjacentSession(offset: Int) {
        let sessions = selectedWorkspace.sessions
        guard !sessions.isEmpty else { return }

        let currentIndex = selectedSessionID.flatMap { id in
            sessions.firstIndex(where: { $0.id == id })
        } ?? 0

        let nextIndex = min(max(currentIndex + offset, 0), sessions.count - 1)
        selectedSessionID = sessions[nextIndex].id
    }

    func selectAdjacentWorkspace(offset: Int) {
        guard let index = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }) else { return }
        let nextIndex = min(max(index + offset, 0), workspaces.count - 1)
        selectedWorkspaceID = workspaces[nextIndex].id
        selectedSessionID = workspaces[nextIndex].sessions.first?.id
        normalize()
    }

    func setWidth(_ preset: WidthPreset, for sessionID: UUID) {
        mutateSession(sessionID) { $0.width = preset }
    }

    func updateTitle(_ title: String, for sessionID: UUID) {
        mutateSession(sessionID) { $0.title = title.isEmpty ? "shell" : title }
    }

    func updatePWD(_ pwd: String, for sessionID: UUID) {
        mutateSession(sessionID) { $0.pwd = pwd }
    }

    func closeSession(_ sessionID: UUID) {
        guard let workspaceIndex = workspaces.firstIndex(where: { workspace in
            workspace.sessions.contains(where: { $0.id == sessionID })
        }) else {
            return
        }

        workspaces[workspaceIndex].sessions.removeAll(where: { $0.id == sessionID })
        if selectedSessionID == sessionID {
            selectedSessionID = workspaces[workspaceIndex].sessions.first?.id
        }
        normalize()
    }

    func session(_ sessionID: UUID) -> Session? {
        workspaces.flatMap(\.sessions).first(where: { $0.id == sessionID })
    }

    private func mutateSession(_ sessionID: UUID, transform: (inout Session) -> Void) {
        for workspaceIndex in workspaces.indices {
            guard let sessionIndex = workspaces[workspaceIndex].sessions.firstIndex(where: { $0.id == sessionID }) else {
                continue
            }
            transform(&workspaces[workspaceIndex].sessions[sessionIndex])
            return
        }
    }

    private func workspaceContaining(_ sessionID: UUID) -> Workspace? {
        workspaces.first(where: { workspace in
            workspace.sessions.contains(where: { $0.id == sessionID })
        })
    }

    private func normalize() {
        var next: [Workspace] = []

        for workspace in workspaces {
            let shouldKeep = !workspace.sessions.isEmpty || workspace.id == selectedWorkspaceID
            if shouldKeep {
                next.append(workspace)
            }
        }

        if next.isEmpty {
            let fallback = Workspace(title: "01")
            next = [fallback]
            selectedWorkspaceID = fallback.id
        }

        let placeholderCount = next.filter { $0.sessions.isEmpty }.count
        if placeholderCount == 0 {
            next.append(Workspace(title: String(format: "%02d", next.count + 1)))
        } else if placeholderCount > 1 {
            var keptPlaceholder = false
            next.removeAll { workspace in
                guard workspace.sessions.isEmpty else { return false }
                if workspace.id == selectedWorkspaceID && !keptPlaceholder {
                    keptPlaceholder = true
                    return false
                }
                if !keptPlaceholder {
                    keptPlaceholder = true
                    return false
                }
                return true
            }
        }

        for index in next.indices {
            next[index].title = String(format: "%02d", index + 1)
        }

        workspaces = next
    }
}

import Foundation

@MainActor
final class GitTileViewModel: ObservableObject {
    @Published private(set) var state: GitTileState = .loading
    @Published private(set) var isRefreshing = false

    var onStateChange: ((GitTileState) -> Void)?

    private var workspaceFolderPath: String?
    private var refreshLoopTask: Task<Void, Never>?
    private var latestRefreshID = UUID()

    func updateWorkspaceFolderPath(_ workspaceFolderPath: String?) {
        let normalizedPath =
            workspaceFolderPath?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard self.workspaceFolderPath != normalizedPath else { return }
        self.workspaceFolderPath = normalizedPath
        state = .loading
        refreshNow()
    }

    func startRefreshing() {
        guard refreshLoopTask == nil else { return }
        refreshLoopTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                await self.refresh()
            }
        }
    }

    func stopRefreshing() {
        refreshLoopTask?.cancel()
        refreshLoopTask = nil
    }

    func refreshNow() {
        Task { [weak self] in
            await self?.refresh()
        }
    }

    private func refresh() async {
        let refreshID = UUID()
        latestRefreshID = refreshID
        isRefreshing = true
        let nextState = await GitTileSnapshotLoader.load(for: workspaceFolderPath)
        guard latestRefreshID == refreshID else { return }
        state = nextState
        isRefreshing = false
        onStateChange?(nextState)
    }
}

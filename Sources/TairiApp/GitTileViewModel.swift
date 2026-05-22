import Foundation

@MainActor
final class GitTileViewModel: ObservableObject {
    @Published private(set) var state: GitTileState = .loading
    @Published private(set) var isRefreshing = false

    var onStateChange: ((GitTileState) -> Void)?

    private var workspaceFolderPath: String?
    private var refreshLoopTask: Task<Void, Never>?
    private var latestRefreshID = UUID()
    private let refreshInterval: Duration
    private let sleep: @MainActor (Duration) async throws -> Void
    private let loadSnapshot: @MainActor (String?) async -> GitTileState

    init(
        refreshInterval: Duration = .seconds(4),
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        loadSnapshot: @escaping @MainActor (String?) async -> GitTileState = { await GitTileSnapshotLoader.load(for: $0) }
    ) {
        self.refreshInterval = refreshInterval
        self.sleep = sleep
        self.loadSnapshot = loadSnapshot
    }

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
                do {
                    try await self.sleep(self.refreshInterval)
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
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
        let nextState = await loadSnapshot(workspaceFolderPath)
        guard latestRefreshID == refreshID else { return }
        state = nextState
        isRefreshing = false
        onStateChange?(nextState)
    }
}

import Foundation
import SwiftUI

@MainActor
final class TileSpotlightController: ObservableObject {
    @Published private(set) var isPresented = false
    @Published var query = ""
    @Published var selectedResultID: UUID?

    func open(selecting tileID: UUID?) {
        query = ""
        selectedResultID = tileID
        isPresented = true
        TairiLog.write("spotlight open selected=\(tileID?.uuidString ?? "none")")
    }

    func close() {
        TairiLog.write(
            "spotlight close query=\(query.debugDescription) selected=\(selectedResultID?.uuidString ?? "none")"
        )
        isPresented = false
        query = ""
        selectedResultID = nil
    }

    func toggle(selecting tileID: UUID?) {
        TairiLog.write("spotlight toggle currentlyPresented=\(isPresented) selected=\(tileID?.uuidString ?? "none")")
        if isPresented {
            close()
        } else {
            open(selecting: tileID)
        }
    }

    func syncSelection(with results: [TileSpotlightResult], preferredID: UUID? = nil) {
        if let selectedResultID,
           results.contains(where: { $0.id == selectedResultID }) {
            return
        }

        if let preferredID,
           results.contains(where: { $0.id == preferredID }) {
            selectedResultID = preferredID
            return
        }

        selectedResultID = results.first?.id
    }

    func moveSelection(delta: Int, within results: [TileSpotlightResult]) {
        guard !results.isEmpty else {
            selectedResultID = nil
            return
        }

        guard let selectedResultID,
              let currentIndex = results.firstIndex(where: { $0.id == selectedResultID }) else {
            self.selectedResultID = results[0].id
            return
        }

        let nextIndex = min(max(currentIndex + delta, 0), results.count - 1)
        self.selectedResultID = results[nextIndex].id
    }

    func selectedResult(in results: [TileSpotlightResult]) -> TileSpotlightResult? {
        guard let selectedResultID else { return results.first }
        return results.first(where: { $0.id == selectedResultID }) ?? results.first
    }
}

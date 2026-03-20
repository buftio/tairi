import XCTest
@testable import TairiApp

@MainActor
final class WorkspaceInteractionControllerTests: XCTestCase {
    private nonisolated(unsafe) var userDefaultsSuiteNames: [String] = []

    override func tearDown() {
        for suiteName in userDefaultsSuiteNames {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        userDefaultsSuiteNames = []
        super.tearDown()
    }

    func testAddTerminalTilePublishesColumnOpenAnimation() throws {
        let store = makeStore()
        let controller = WorkspaceInteractionController(store: store)
        let tileID = try XCTUnwrap(store.selectedTileID)

        let tile = controller.addTerminalTile(
            nextTo: tileID,
            sessionID: UUID(),
            transition: .animatedReveal
        )
        let animation = try XCTUnwrap(controller.tileOpenAnimation)

        XCTAssertEqual(animation.tileID, tile.id)
        XCTAssertTrue(animation.animated)
        XCTAssertEqual(animation.kind, .columnOpen)
    }

    func testSplitTerminalTilePublishesVerticalSplitOpenAnimation() throws {
        let store = makeStore()
        let controller = WorkspaceInteractionController(store: store)
        let sourceTileID = try XCTUnwrap(store.selectedTileID)

        let tile = try XCTUnwrap(
            controller.splitTerminalTile(
                sourceTileID,
                sessionID: UUID(),
                transition: .animatedReveal
            )
        )
        let animation = try XCTUnwrap(controller.tileOpenAnimation)

        XCTAssertEqual(animation.tileID, tile.id)
        XCTAssertTrue(animation.animated)
        XCTAssertEqual(animation.kind, .verticalSplit(sourceTileID: sourceTileID))
    }

    private func makeStore() -> WorkspaceStore {
        WorkspaceStore(
            initialTerminalWorkingDirectory: "/tmp/dev-root",
            sidebarPersistence: makeSidebarPersistence()
        )
    }

    private func makeSidebarPersistence() -> WorkspaceSidebarPersistence {
        let suiteName = "WorkspaceInteractionControllerTests.\(UUID().uuidString)"
        userDefaultsSuiteNames.append(suiteName)
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return WorkspaceSidebarPersistence(userDefaults: userDefaults)
    }
}

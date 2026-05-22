import XCTest

@testable import TairiApp

@MainActor
final class GitTileViewModelTests: XCTestCase {
    func testStopRefreshingCancelsSleepingLoopWithoutAnotherRefresh() async {
        let initialLoad = expectation(description: "initial load")
        let sleepStarted = expectation(description: "sleep started")
        let extraLoad = expectation(description: "extra load")
        extraLoad.isInverted = true
        var loadCount = 0

        let model = GitTileViewModel(
            refreshInterval: .seconds(60),
            sleep: { _ in
                sleepStarted.fulfill()
                try await Task.sleep(for: .seconds(60))
            },
            loadSnapshot: { _ in
                loadCount += 1
                if loadCount == 1 {
                    initialLoad.fulfill()
                } else {
                    extraLoad.fulfill()
                }
                return .noFolder
            }
        )

        model.startRefreshing()
        await fulfillment(of: [initialLoad, sleepStarted], timeout: 1)
        model.stopRefreshing()
        await fulfillment(of: [extraLoad], timeout: 0.2)

        XCTAssertEqual(loadCount, 1)
    }
}

import XCTest
@testable import WhiskyKit

final class BottleCreationActivityStateTests: XCTestCase {
    func testFailedPreflightClearsBusyStateAndAllowsRetry() {
        var state = BottleCreationActivityState()

        XCTAssertTrue(state.begin())
        XCTAssertTrue(state.isBusy)
        state.finish(.failed)

        XCTAssertFalse(state.isBusy)
        XCTAssertTrue(state.canStart)
        XCTAssertTrue(state.begin())
    }

    func testCancellationClearsBusyStateAndAllowsRetry() {
        var state = BottleCreationActivityState()

        XCTAssertTrue(state.begin())
        state.finish(.cancelled)

        XCTAssertFalse(state.isBusy)
        XCTAssertTrue(state.canStart)
    }

    func testRelaunchAfterFailureStartsUsable() {
        var failedSession = BottleCreationActivityState()
        XCTAssertTrue(failedSession.begin())
        failedSession.finish(.failed)

        let relaunchedSession = BottleCreationActivityState()
        XCTAssertFalse(relaunchedSession.isBusy)
        XCTAssertTrue(relaunchedSession.canStart)
        XCTAssertEqual(relaunchedSession.outcome, .idle)
    }
}

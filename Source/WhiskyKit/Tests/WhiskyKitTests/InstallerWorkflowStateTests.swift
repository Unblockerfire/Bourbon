import XCTest
@testable import WhiskyKit

final class InstallerWorkflowStateTests: XCTestCase {
    func testRunningProgressAndCancellation() {
        var workflow = InstallerWorkflow()
        let id = workflow.start(detail: "Opening...")
        XCTAssertEqual(workflow.state, .running)
        XCTAssertTrue(workflow.presentsProgress)
        XCTAssertTrue(workflow.showsSpinner)
        XCTAssertTrue(workflow.canCancel)
        XCTAssertTrue(workflow.update(activity: .installing, detail: "Installing...", for: id))
    }

    func testFinalizationCannotSucceedOrCancelPrematurely() {
        var workflow = InstallerWorkflow()
        let id = workflow.start(detail: "Opening...")
        XCTAssertFalse(workflow.succeed(detail: "Finished.", for: id))
        XCTAssertTrue(workflow.beginFinalization(detail: "Refreshing...", for: id))
        XCTAssertTrue(workflow.presentsProgress)
        XCTAssertTrue(workflow.showsSpinner)
        XCTAssertFalse(workflow.canCancel)
        XCTAssertFalse(workflow.beginCancellation(detail: "Cancelling...", for: id))
        XCTAssertFalse(workflow.hasEmittedSuccess)
    }

    func testSuccessIsTerminalAndEmitsOnce() {
        var workflow = InstallerWorkflow()
        let id = workflow.start(detail: "Opening...")
        XCTAssertTrue(workflow.beginFinalization(detail: "Refreshing...", for: id))
        XCTAssertTrue(workflow.succeed(detail: "Finished.", for: id))
        XCTAssertFalse(workflow.succeed(detail: "Again.", for: id))
        XCTAssertEqual(workflow.state, .succeeded)
        XCTAssertEqual(workflow.activity, .done)
        XCTAssertFalse(workflow.presentsProgress)
        XCTAssertFalse(workflow.showsSpinner)
        XCTAssertFalse(workflow.canCancel)
    }

    func testCancellationAndLateCallbacksCannotSucceed() {
        var workflow = InstallerWorkflow()
        let cancelledID = workflow.start(detail: "Opening...")
        XCTAssertTrue(workflow.beginCancellation(detail: "Cancelling...", for: cancelledID))
        XCTAssertTrue(workflow.cancel(detail: "Cancelled.", for: cancelledID))
        XCTAssertFalse(workflow.succeed(detail: "Late success.", for: cancelledID))

        let oldID = workflow.start(detail: "Opening...")
        XCTAssertTrue(workflow.beginFinalization(detail: "Refreshing...", for: oldID))
        XCTAssertTrue(workflow.fail(detail: "Failed.", for: oldID))
        XCTAssertFalse(workflow.succeed(detail: "Late success.", for: oldID))
        let newID = workflow.start(detail: "Opening new...")
        XCTAssertFalse(workflow.update(activity: .installing, detail: "Late callback.", for: oldID))
        XCTAssertFalse(workflow.fail(detail: "Late failure.", for: oldID))
        XCTAssertEqual(workflow.installID, newID)
    }
}

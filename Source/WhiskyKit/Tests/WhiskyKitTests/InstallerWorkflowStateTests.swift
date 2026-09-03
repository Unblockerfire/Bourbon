import XCTest
@testable import WhiskyKit

final class InstallerWorkflowStateTests: XCTestCase {
    func testOnlyRunningInstallationCanBeCancelled() {
        XCTAssertTrue(InstallerWorkflowState.running.isActive)
        XCTAssertTrue(InstallerWorkflowState.running.canCancel)

        XCTAssertTrue(InstallerWorkflowState.finalizing.isActive)
        XCTAssertFalse(InstallerWorkflowState.finalizing.canCancel)

        XCTAssertTrue(InstallerWorkflowState.cancelling.isActive)
        XCTAssertFalse(InstallerWorkflowState.cancelling.canCancel)
    }

    func testTerminalStatesAreNotActiveOrCancellable() {
        for state in [
            InstallerWorkflowState.succeeded,
            .failed,
            .cancelled
        ] {
            XCTAssertTrue(state.isTerminal)
            XCTAssertFalse(state.isActive)
            XCTAssertFalse(state.canCancel)
        }
    }

    func testFinalizationIsNotReportedAsSuccess() {
        XCTAssertFalse(InstallerWorkflowState.finalizing.isTerminal)
        XCTAssertFalse(InstallerWorkflowState.finalizing == .succeeded)
    }
}

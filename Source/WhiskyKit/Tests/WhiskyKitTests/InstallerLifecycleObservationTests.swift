import XCTest
@testable import WhiskyKit

final class InstallerLifecycleObservationTests: XCTestCase {
    func testNormalLauncherExitContinuesToFinalization() {
        let observation = InstallerLifecycleObservation(
            launcherIsRunning: false,
            launcherExitStatus: 0,
            targetProcessIsRunning: false,
            childWineProcessCount: 0,
            wineDebuggerIsRunning: false
        )
        XCTAssertEqual(InstallerLifecycleClassifier.decision(for: observation), .continueWaiting)

        var workflow = InstallerWorkflow()
        let id = workflow.start(detail: "Installing")
        XCTAssertTrue(workflow.beginFinalization(detail: "Refreshing", for: id))
        XCTAssertTrue(workflow.succeed(detail: "Complete", for: id))
        XCTAssertEqual(workflow.state, .succeeded)
    }

    func testNonzeroExitWithoutRemainingTargetFails() {
        let observation = InstallerLifecycleObservation(
            launcherIsRunning: false,
            launcherExitStatus: 1,
            targetProcessIsRunning: false,
            childWineProcessCount: 0,
            wineDebuggerIsRunning: false
        )
        XCTAssertEqual(
            InstallerLifecycleClassifier.decision(for: observation),
            .failed("The installer launcher exited with status 1.")
        )
    }

    func testWineDebuggerFailsEvenWhileLauncherRemainsRunning() {
        let observation = InstallerLifecycleObservation(
            launcherPID: 42,
            launcherIsRunning: true,
            targetProcessIsRunning: true,
            childWineProcessCount: 3,
            wineDebuggerIsRunning: true
        )
        XCTAssertEqual(
            InstallerLifecycleClassifier.decision(for: observation),
            .failed("Wine entered its crash debugger while this installer was active.")
        )
    }

    func testLongRunningInstallerAloneDoesNotFail() {
        let observation = InstallerLifecycleObservation(
            launcherPID: 42,
            launcherIsRunning: true,
            targetProcessIsRunning: true,
            childWineProcessCount: 2,
            wineDebuggerIsRunning: false
        )
        XCTAssertEqual(InstallerLifecycleClassifier.decision(for: observation), .continueWaiting)
    }

    func testFailedWorkflowStopsWaitingAndCanRetry() {
        var workflow = InstallerWorkflow()
        let id = workflow.start(detail: "Waiting for installer to finish...")
        XCTAssertTrue(workflow.fail(detail: "Wine entered its crash debugger.", for: id))
        XCTAssertEqual(workflow.state, .failed)
        XCTAssertFalse(workflow.showsSpinner)
        XCTAssertTrue(workflow.canStart)
    }

    func testCancellationRemainsCancellation() {
        var workflow = InstallerWorkflow()
        let id = workflow.start(detail: "Installing")
        XCTAssertTrue(workflow.beginCancellation(detail: "Stopping", for: id))
        XCTAssertTrue(workflow.cancel(detail: "Cancelled", for: id))
        XCTAssertEqual(workflow.state, .cancelled)
    }
}

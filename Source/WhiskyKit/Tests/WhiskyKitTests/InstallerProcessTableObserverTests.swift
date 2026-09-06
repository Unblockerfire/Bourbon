import XCTest
@testable import WhiskyKit

final class InstallerProcessTableObserverTests: XCTestCase {
    @MainActor
    func testProcessInspectionYieldsMainActorWhileItRuns() async {
        let command = InstallerProcessTableCommand(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 0.2; printf 'WINEPREFIX=/tmp/test wine'"],
            matchingPrefix: "/tmp/test",
            timeout: .seconds(2)
        )
        let mainActorWasAvailable = expectation(description: "MainActor remained available")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            mainActorWasAvailable.fulfill()
        }

        let result = await command.collect()

        await fulfillment(of: [mainActorWasAvailable], timeout: 1)
        XCTAssertEqual(result.status, .complete)
        XCTAssertEqual(result.scopedLines.count, 1)
    }

    func testLargeProcessOutputIsDrainedBeforeTermination() async {
        let command = InstallerProcessTableCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/seq"),
            arguments: ["1", "250000"],
            matchingPrefix: "/prefix/that-is-not-present",
            timeout: .seconds(5)
        )

        let result = await command.collect()

        XCTAssertEqual(result.status, .complete)
        XCTAssertTrue(result.scopedLines.isEmpty)
    }

    func testInspectionTimeoutReturnsConservativeObservation() async {
        let request = InstallerLifecycleObservationRequest(
            prefixPath: "/tmp/test-prefix",
            targetExecutableName: "installer.exe",
            lifecycle: nil
        )
        let observer = InstallerProcessTableObserver { _ in
            InstallerProcessTableAcquisition(scopedLines: [], status: .timedOut)
        }

        let observation = await observer.observe(request)

        XCTAssertEqual(observation.processTableStatus, .timedOut)
        XCTAssertEqual(InstallerLifecycleClassifier.decision(for: observation), .continueWaiting)
    }

    func testDiagnosticCommandTimeoutDoesNotBlockCollection() async {
        let command = InstallerProcessTableCommand(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 5"],
            matchingPrefix: "/tmp/test-prefix",
            timeout: .milliseconds(50)
        )

        let result = await command.collect()

        XCTAssertEqual(result.status, .timedOut)
        XCTAssertTrue(result.scopedLines.isEmpty)
    }

    @MainActor
    func testRepeatedObservationPollingYieldsMainActor() async {
        let request = InstallerLifecycleObservationRequest(
            prefixPath: "/tmp/test-prefix",
            targetExecutableName: "installer.exe",
            lifecycle: nil
        )
        let observer = InstallerProcessTableObserver { _ in
            try? await Task.sleep(for: .milliseconds(10))
            return InstallerProcessTableAcquisition(scopedLines: [], status: .complete)
        }
        let mainActorWasAvailable = expectation(description: "MainActor continued servicing work")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(25))
            mainActorWasAvailable.fulfill()
        }

        for _ in 0..<10 {
            _ = await observer.observe(request)
        }

        await fulfillment(of: [mainActorWasAvailable], timeout: 1)
    }
}

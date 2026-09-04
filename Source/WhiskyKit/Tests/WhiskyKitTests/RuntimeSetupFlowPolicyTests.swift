import XCTest
@testable import WhiskyKit

final class RuntimeSetupFlowPolicyTests: XCTestCase {
    func testAutomaticFlowContinuesForEveryStateThatNeedsReplacement() {
        for state in [
            RuntimeDiscovery.State.missing,
            .installedUnverified,
            .corruptOrIncomplete,
            .unsupported,
            .verificationFailed
        ] {
            XCTAssertEqual(
                RuntimeSetupFlowPolicy.automaticDownloadAction(for: state),
                .continueDownload,
                "\(state) must not dismiss the automatic installer flow"
            )
        }
    }

    func testReadyRecheckDoesNotDismissAnActiveAutomaticFlow() {
        XCTAssertEqual(
            RuntimeSetupFlowPolicy.automaticDownloadAction(for: .ready),
            .showReadyWithoutDismissing
        )
    }

    func testManualArchiveSelectionSupersedesAutomaticDownload() {
        XCTAssertTrue(RuntimeSetupFlowPolicy.manualArchiveSupersedesAutomaticDownload)
    }
}

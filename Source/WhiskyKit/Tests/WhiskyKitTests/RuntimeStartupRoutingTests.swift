import XCTest
@testable import WhiskyKit

final class RuntimeStartupRoutingTests: XCTestCase {
    func testCompletedOnboardingWithReadyRuntimeOpensHome() {
        XCTAssertEqual(
            RuntimeStartupRouting.route(onboardingCompleted: true, runtimeState: .ready),
            .home
        )
    }

    func testCompletedOnboardingWithMissingRuntimeOpensRepair() {
        XCTAssertEqual(
            RuntimeStartupRouting.route(onboardingCompleted: true, runtimeState: .missing),
            .runtimeRepair
        )
    }

    func testCompletedOnboardingWithGatekeeperBlockedRuntimeOpensRecovery() {
        XCTAssertEqual(
            RuntimeStartupRouting.route(onboardingCompleted: true, runtimeState: .gatekeeperBlocked),
            .gatekeeperRecovery
        )
    }

    func testCompletedOnboardingWithInvalidRuntimeOpensRepair() {
        for state in [
            RuntimeDiscovery.State.installedUnverified,
            .corruptOrIncomplete,
            .unsupported,
            .verificationFailed
        ] {
            XCTAssertEqual(
                RuntimeStartupRouting.route(onboardingCompleted: true, runtimeState: state),
                .runtimeRepair
            )
        }
    }
}

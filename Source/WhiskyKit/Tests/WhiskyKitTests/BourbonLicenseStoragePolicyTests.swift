import XCTest
@testable import WhiskyKit

final class BourbonLicenseStoragePolicyTests: XCTestCase {
    func testDiagnosticReadsItsMetadataBeforeProductionFallback() {
        XCTAssertEqual(
            BourbonLicenseStoragePolicy.metadataBundleIdentifiers(
                for: BourbonLicenseStoragePolicy.diagnosticBundleIdentifier
            ),
            [
                BourbonLicenseStoragePolicy.diagnosticBundleIdentifier,
                BourbonLicenseStoragePolicy.productionBundleIdentifier
            ]
        )
    }

    func testProductionUsesOnlyProductionMetadata() {
        XCTAssertEqual(
            BourbonLicenseStoragePolicy.metadataBundleIdentifiers(
                for: BourbonLicenseStoragePolicy.productionBundleIdentifier
            ),
            [BourbonLicenseStoragePolicy.productionBundleIdentifier]
        )
    }

    func testDiagnosticAndProductionTokensUseDifferentAccounts() {
        XCTAssertEqual(
            BourbonLicenseStoragePolicy.tokenAccount(
                for: BourbonLicenseStoragePolicy.diagnosticBundleIdentifier
            ),
            BourbonLicenseStoragePolicy.diagnosticTokenAccount
        )
        XCTAssertEqual(
            BourbonLicenseStoragePolicy.tokenAccount(
                for: BourbonLicenseStoragePolicy.productionBundleIdentifier
            ),
            BourbonLicenseStoragePolicy.productionTokenAccount
        )
    }

    func testMissingDiagnosticMetadataFallsBackToProductionWithoutCopyingIt() {
        let resolved = BourbonLicenseStoragePolicy.resolvedMetadataBundleIdentifier(
            for: BourbonLicenseStoragePolicy.diagnosticBundleIdentifier,
            availableBundleIdentifiers: [BourbonLicenseStoragePolicy.productionBundleIdentifier]
        )
        XCTAssertEqual(resolved, BourbonLicenseStoragePolicy.productionBundleIdentifier)
    }

    func testCoexistingDiagnosticMetadataDoesNotReplaceProductionMetadata() {
        let resolved = BourbonLicenseStoragePolicy.resolvedMetadataBundleIdentifier(
            for: BourbonLicenseStoragePolicy.diagnosticBundleIdentifier,
            availableBundleIdentifiers: [
                BourbonLicenseStoragePolicy.productionBundleIdentifier,
                BourbonLicenseStoragePolicy.diagnosticBundleIdentifier
            ]
        )
        XCTAssertEqual(resolved, BourbonLicenseStoragePolicy.diagnosticBundleIdentifier)
    }

    func testDiagnosticCannotMutateProductionLicenseState() {
        XCTAssertFalse(
            BourbonLicenseStoragePolicy.mayMutateProductionState(
                bundleIdentifier: BourbonLicenseStoragePolicy.diagnosticBundleIdentifier
            )
        )
        XCTAssertTrue(
            BourbonLicenseStoragePolicy.mayMutateProductionState(
                bundleIdentifier: BourbonLicenseStoragePolicy.productionBundleIdentifier
            )
        )
    }

    func testSuccessfulLicenseActivityClearsBusyState() {
        var state = BourbonLicenseActivityState()
        let requestID = state.begin()
        XCTAssertTrue(state.isBusy)
        XCTAssertTrue(state.finish(requestID))
        XCTAssertFalse(state.isBusy)
    }

    func testCancelledLicenseActivityClearsBusyState() {
        var state = BourbonLicenseActivityState()
        state.begin()
        state.cancel()
        XCTAssertFalse(state.isBusy)
    }

    func testStaleCompletionCannotFinishNewerLicenseActivity() {
        var state = BourbonLicenseActivityState()
        let staleRequestID = state.begin()
        let currentRequestID = state.begin()
        XCTAssertFalse(state.finish(staleRequestID))
        XCTAssertTrue(state.isBusy)
        XCTAssertTrue(state.finish(currentRequestID))
        XCTAssertFalse(state.isBusy)
    }
}

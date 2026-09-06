import XCTest
@testable import WhiskyKit

final class OnboardingLicenseStateTests: XCTestCase {
    func testFirstRunWithoutLicenseCanCreateOne() {
        let state = OnboardingLicenseState.resolve(
            hasCompletedFirstRun: false, hasStoredLicense: false, storedLicenseIsRejected: false
        )
        XCTAssertEqual(state, .firstRunNeedsLicense)
        XCTAssertTrue(state.permitsNewLicenseCreation)
    }

    func testFirstRunWithStoredLicenseDoesNotCreateAnother() {
        let state = OnboardingLicenseState.resolve(
            hasCompletedFirstRun: false, hasStoredLicense: true, storedLicenseIsRejected: false
        )
        XCTAssertEqual(state, .firstRunHasStoredLicense)
        XCTAssertFalse(state.permitsNewLicenseCreation)
    }

    func testReturningValidLicenseProceedsNormally() {
        XCTAssertEqual(
            OnboardingLicenseState.resolve(
                hasCompletedFirstRun: true, hasStoredLicense: true, storedLicenseIsRejected: false
            ), .returningValid
        )
    }

    func testReturningMissingLicenseRequiresRecoveryInsteadOfCreation() {
        let state = OnboardingLicenseState.resolve(
            hasCompletedFirstRun: true, hasStoredLicense: false, storedLicenseIsRejected: false
        )
        XCTAssertEqual(state, .returningMissing)
        XCTAssertTrue(state.requiresRecovery)
        XCTAssertFalse(state.permitsNewLicenseCreation)
    }

    func testReturningRejectedLicenseRequiresRecoveryInsteadOfCreation() {
        let state = OnboardingLicenseState.resolve(
            hasCompletedFirstRun: true, hasStoredLicense: true, storedLicenseIsRejected: true
        )
        XCTAssertEqual(state, .returningInvalid)
        XCTAssertTrue(state.requiresRecovery)
        XCTAssertFalse(state.permitsNewLicenseCreation)
    }
}

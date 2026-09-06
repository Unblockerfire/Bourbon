import Foundation

/// The durable onboarding facts are deliberately translated into one state before a
/// view decides which action to offer. This prevents a missing Keychain item from
/// turning a returning person into a new account creation flow.
public enum OnboardingLicenseState: Equatable, Sendable {
    case firstRunNeedsLicense
    case firstRunHasStoredLicense
    case returningValid
    case returningMissing
    case returningInvalid

    public var permitsNewLicenseCreation: Bool {
        self == .firstRunNeedsLicense
    }

    public var requiresRecovery: Bool {
        switch self {
        case .returningMissing, .returningInvalid:
            true
        case .firstRunNeedsLicense, .firstRunHasStoredLicense, .returningValid:
            false
        }
    }

    public static func resolve(
        hasCompletedFirstRun: Bool,
        hasStoredLicense: Bool,
        storedLicenseIsRejected: Bool
    ) -> Self {
        if hasCompletedFirstRun {
            if storedLicenseIsRejected { return .returningInvalid }
            return hasStoredLicense ? .returningValid : .returningMissing
        }
        return hasStoredLicense ? .firstRunHasStoredLicense : .firstRunNeedsLicense
    }
}

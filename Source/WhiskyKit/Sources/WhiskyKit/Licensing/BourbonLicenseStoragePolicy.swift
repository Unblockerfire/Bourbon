//
//  BourbonLicenseStoragePolicy.swift
//  WhiskyKit
//

import Foundation

/// Defines which non-secret metadata and Keychain account Bourbon may use for
/// production and diagnostic builds. Diagnostic builds may read production
/// state, but they must never mutate it.
public enum BourbonLicenseStoragePolicy {
    public static let productionBundleIdentifier = "com.unblockerfire.Bourbon"
    public static let diagnosticBundleIdentifier = "com.unblockerfire.BourbonDiagnostic"
    public static let productionTokenAccount = "license-token"
    public static let diagnosticTokenAccount = "license-token-diagnostic"

    public static func isDiagnostic(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == diagnosticBundleIdentifier
    }

    public static func metadataBundleIdentifiers(for bundleIdentifier: String?) -> [String] {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            return [productionBundleIdentifier]
        }
        if isDiagnostic(bundleIdentifier: bundleIdentifier) {
            return [diagnosticBundleIdentifier, productionBundleIdentifier]
        }
        return [bundleIdentifier]
    }

    public static func tokenAccount(for metadataBundleIdentifier: String) -> String {
        metadataBundleIdentifier == diagnosticBundleIdentifier
            ? diagnosticTokenAccount
            : productionTokenAccount
    }

    public static func resolvedMetadataBundleIdentifier(
        for bundleIdentifier: String?,
        availableBundleIdentifiers: Set<String>
    ) -> String? {
        metadataBundleIdentifiers(for: bundleIdentifier).first {
            availableBundleIdentifiers.contains($0)
        }
    }

    public static func mayMutateProductionState(bundleIdentifier: String?) -> Bool {
        !isDiagnostic(bundleIdentifier: bundleIdentifier)
    }
}

/// Request identity used by the license UI so completion from a cancelled or
/// superseded task cannot leave a newer activity busy or replace its result.
public struct BourbonLicenseActivityState: Equatable, Sendable {
    public private(set) var activeRequestID: UUID?

    public init(activeRequestID: UUID? = nil) {
        self.activeRequestID = activeRequestID
    }

    public var isBusy: Bool {
        activeRequestID != nil
    }

    @discardableResult
    public mutating func begin() -> UUID {
        let requestID = UUID()
        activeRequestID = requestID
        return requestID
    }

    public mutating func cancel() {
        activeRequestID = nil
    }

    @discardableResult
    public mutating func finish(_ requestID: UUID) -> Bool {
        guard activeRequestID == requestID else { return false }
        activeRequestID = nil
        return true
    }
}

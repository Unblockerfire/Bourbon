//
//  RuntimeSetupFlowPolicy.swift
//  WhiskyKit
//

import Foundation

/// Keeps a background runtime recheck from replacing an installer flow the
/// user has already chosen. Presentation is completed only by an explicit
/// cancellation or a verified installation result.
public enum RuntimeSetupFlowPolicy {
    public enum AutomaticDownloadAction: Equatable, Sendable {
        case continueDownload
        case showReadyWithoutDismissing
        case showGatekeeperRecovery
    }

    public static func automaticDownloadAction(
        for runtimeState: RuntimeDiscovery.State
    ) -> AutomaticDownloadAction {
        switch runtimeState {
        case .ready:
            // The setup check may have been stale or preflight may have
            // completed between the check and this recheck. Do not pop UI.
            return .showReadyWithoutDismissing
        case .gatekeeperBlocked:
            return .showGatekeeperRecovery
        case .missing, .installedUnverified, .corruptOrIncomplete, .unsupported, .verificationFailed:
            return .continueDownload
        }
    }

    /// Selecting a local archive must supersede, rather than race, the active
    /// automatic URLSession attempt.
    public static var manualArchiveSupersedesAutomaticDownload: Bool { true }
}

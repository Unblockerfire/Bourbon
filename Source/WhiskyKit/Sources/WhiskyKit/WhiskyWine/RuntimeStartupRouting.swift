//
//  RuntimeStartupRouting.swift
//  WhiskyKit
//

import Foundation

public enum RuntimeStartupRoute: Equatable, Sendable {
    case onboarding
    case home
    case runtimeRepair
    case gatekeeperRecovery
}

public enum RuntimeStartupRouting {
    public static func route(
        onboardingCompleted: Bool,
        runtimeState: RuntimeDiscovery.State?
    ) -> RuntimeStartupRoute {
        guard onboardingCompleted else { return .onboarding }
        guard let runtimeState else { return .runtimeRepair }

        switch runtimeState {
        case .ready:
            return .home
        case .gatekeeperBlocked:
            return .gatekeeperRecovery
        case .missing, .installedUnverified, .corruptOrIncomplete, .unsupported, .verificationFailed:
            return .runtimeRepair
        }
    }
}

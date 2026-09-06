//
//  InstallerLifecycleObservation.swift
//  WhiskyKit
//

import Foundation

/// A redacted, bottle-scoped observation used to decide whether an active
/// installer can still reasonably be presented as running.
public struct InstallerLifecycleObservation: Equatable, Sendable {
    public let launcherPID: Int32?
    public let launcherIsRunning: Bool
    public let launcherExitStatus: Int32?
    public let targetProcessIsRunning: Bool
    public let childWineProcessCount: Int
    public let wineDebuggerIsRunning: Bool
    public let processTableStatus: InstallerProcessTableStatus

    public init(
        launcherPID: Int32? = nil,
        launcherIsRunning: Bool,
        launcherExitStatus: Int32? = nil,
        targetProcessIsRunning: Bool,
        childWineProcessCount: Int,
        wineDebuggerIsRunning: Bool,
        processTableStatus: InstallerProcessTableStatus = .complete
    ) {
        self.launcherPID = launcherPID
        self.launcherIsRunning = launcherIsRunning
        self.launcherExitStatus = launcherExitStatus
        self.targetProcessIsRunning = targetProcessIsRunning
        self.childWineProcessCount = childWineProcessCount
        self.wineDebuggerIsRunning = wineDebuggerIsRunning
        self.processTableStatus = processTableStatus
    }
}

public enum InstallerLifecycleDecision: Equatable, Sendable {
    case continueWaiting
    case failed(String)
}

/// Deliberately has no elapsed-time input: a long-running installer is not a
/// failure. Only concrete exit/debugger evidence can end the active workflow.
public enum InstallerLifecycleClassifier {
    public static func decision(for observation: InstallerLifecycleObservation) -> InstallerLifecycleDecision {
        if observation.wineDebuggerIsRunning {
            return .failed("Wine entered its crash debugger while this installer was active.")
        }

        if let status = observation.launcherExitStatus, status != 0,
           !observation.targetProcessIsRunning, observation.childWineProcessCount == 0 {
            return .failed("The installer launcher exited with status \(status).")
        }

        return .continueWaiting
    }
}

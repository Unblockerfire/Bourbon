//
//  InstallerWorkflowState.swift
//  WhiskyKit
//

import Foundation

/// The single authoritative lifecycle for a Bourbon installer workflow.
///
/// A child installer exiting is not success by itself: the workflow remains in
/// `finalizing` until Bourbon has refreshed the bottle's installed applications.
public enum InstallerWorkflowState: Equatable, Sendable {
    case idle
    case running
    case finalizing
    case cancelling
    case succeeded
    case failed
    case cancelled

    public var isActive: Bool {
        switch self {
        case .running, .finalizing, .cancelling:
            return true
        case .idle, .succeeded, .failed, .cancelled:
            return false
        }
    }

    public var canCancel: Bool {
        self == .running
    }

    public var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled:
            return true
        case .idle, .running, .finalizing, .cancelling:
            return false
        }
    }
}

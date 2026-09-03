//
//  InstallerWorkflowState.swift
//  WhiskyKit
//

import Foundation

/// The terminal and non-terminal states of one Windows-installer workflow.
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

/// Ordered presentation milestones. `done` is a terminal presentation, not work.
public enum InstallerWorkflowActivity: Int, CaseIterable, Equatable, Sendable {
    case opening
    case looking
    case metadata
    case architecture
    case searching
    case preparing
    case launching
    case installing
    case recovering
    case refreshing
    case done
}

/// The single authoritative, install-ID-scoped state machine.
public struct InstallerWorkflow: Equatable, Sendable {
    public private(set) var installID: UUID?
    public private(set) var state: InstallerWorkflowState = .idle
    public private(set) var activity: InstallerWorkflowActivity = .opening
    public private(set) var detail = ""
    public private(set) var hasEmittedSuccess = false

    public init() {}

    public var presentsProgress: Bool { state.isActive }
    public var showsSpinner: Bool { state.isActive }
    public var canCancel: Bool { state.canCancel }
    public var canStart: Bool { !state.isActive }

    @discardableResult
    public mutating func start(detail: String) -> UUID {
        let id = UUID()
        installID = id
        state = .running
        activity = .opening
        self.detail = detail
        hasEmittedSuccess = false
        return id
    }

    @discardableResult
    public mutating func update(activity: InstallerWorkflowActivity, detail: String, for installID: UUID) -> Bool {
        guard self.installID == installID, state == .running else { return false }
        self.activity = activity
        self.detail = detail
        return true
    }

    @discardableResult
    public mutating func beginFinalization(detail: String, for installID: UUID) -> Bool {
        guard self.installID == installID, state == .running else { return false }
        state = .finalizing
        activity = .refreshing
        self.detail = detail
        return true
    }

    @discardableResult
    public mutating func succeed(detail: String, for installID: UUID) -> Bool {
        guard self.installID == installID, state == .finalizing, !hasEmittedSuccess else { return false }
        state = .succeeded
        activity = .done
        self.detail = detail
        hasEmittedSuccess = true
        return true
    }

    @discardableResult
    public mutating func beginCancellation(detail: String, for installID: UUID) -> Bool {
        guard self.installID == installID, state == .running else { return false }
        state = .cancelling
        self.detail = detail
        return true
    }

    @discardableResult
    public mutating func cancel(detail: String, for installID: UUID) -> Bool {
        guard self.installID == installID, state == .cancelling else { return false }
        state = .cancelled
        self.detail = detail
        return true
    }

    @discardableResult
    public mutating func fail(detail: String, for installID: UUID) -> Bool {
        guard self.installID == installID, state.isActive else { return false }
        state = .failed
        self.detail = detail
        return true
    }

    public mutating func clearTerminalState() {
        guard state.isTerminal else { return }
        installID = nil
        state = .idle
        activity = .opening
        detail = ""
        hasEmittedSuccess = false
    }
}

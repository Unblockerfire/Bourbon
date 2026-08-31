//
//  BottleCreationActivityState.swift
//  WhiskyKit
//

import Foundation

public struct BottleCreationActivityState: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case idle
        case running
        case succeeded
        case failed
        case cancelled
    }

    public private(set) var outcome: Outcome = .idle

    public init() {}

    public var isBusy: Bool { outcome == .running }
    public var canStart: Bool { !isBusy }

    @discardableResult
    public mutating func begin() -> Bool {
        guard canStart else { return false }
        outcome = .running
        return true
    }

    public mutating func finish(_ outcome: Outcome) {
        precondition(outcome != .running, "A completed creation cannot remain running.")
        self.outcome = outcome
    }
}

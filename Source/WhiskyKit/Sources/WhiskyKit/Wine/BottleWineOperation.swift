//
//  BottleWineOperation.swift
//  WhiskyKit
//

import Darwin
import Foundation
import OSLog

public enum BottleWineOperationError: LocalizedError, Equatable, Sendable {
    case duplicateInvocation(phase: String)
    case wineInitializationTimeout
    case wineConfigurationTimeout
    case wineSettlementTimeout
    case wineCancellationTimeout

    public var diagnosticCode: String {
        switch self {
        case .duplicateInvocation:
            return "wine_duplicate_invocation"
        case .wineInitializationTimeout:
            return "wine_initialization_timeout"
        case .wineConfigurationTimeout:
            return "wine_configuration_timeout"
        case .wineSettlementTimeout:
            return "wine_settlement_timeout"
        case .wineCancellationTimeout:
            return "wine_cancellation_timeout"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .duplicateInvocation:
            return "Bourbon stopped a repeated Bottle setup command."
        case .wineInitializationTimeout, .wineConfigurationTimeout, .wineSettlementTimeout:
            return "BourbonWine did not finish setting up this Bottle. Bourbon stopped the setup process so " +
                "Wine would not continue running in the background. You can try creating the Bottle again."
        case .wineCancellationTimeout:
            return "Bourbon stopped Bottle creation, but BourbonWine took too long to finish cleanup."
        }
    }
}

/// Owns only the temporary Wine processes started while one Bottle is being created.
/// Normal user-launched programs never register with this object.
public final class BottleWineOperation: @unchecked Sendable {
    public let id: UUID
    public let bottleIdentifier: String

    private let lock = NSLock()
    private var invocationCounts: [String: Int] = [:]
    private var processes: [Int32: Process] = [:]
    private var cancellationRequested = false
    private var completed = false

    public init(prefixURL: URL, id: UUID = UUID()) {
        self.id = id
        self.bottleIdentifier = prefixURL.lastPathComponent
    }

    @discardableResult
    public func beginSingleInvocation(phase: String, command: [String]) throws -> Int {
        lock.lock()
        let attempt = (invocationCounts[phase] ?? 0) + 1
        invocationCounts[phase] = attempt
        lock.unlock()

        record(
            "bottle.create.wine.launch phase=\(phase) command=\(safeCommand(command)) attempt=\(attempt)"
        )
        guard attempt == 1 else {
            throw BottleWineOperationError.duplicateInvocation(phase: phase)
        }
        return attempt
    }

    @discardableResult
    public func beginInvocation(phase: String, command: [String]) -> Int {
        lock.lock()
        let attempt = (invocationCounts[phase] ?? 0) + 1
        invocationCounts[phase] = attempt
        lock.unlock()
        record(
            "bottle.create.wine.launch phase=\(phase) command=\(safeCommand(command)) attempt=\(attempt)"
        )
        return attempt
    }

    public func invocationCount(for phase: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return invocationCounts[phase] ?? 0
    }

    public func register(_ process: Process, phase: String) {
        lock.lock()
        processes[process.processIdentifier] = process
        let shouldTerminate = cancellationRequested
        lock.unlock()

        record(
            "bottle.create.wine.process.started phase=\(phase) pid=\(process.processIdentifier) " +
                "parent_pid=\(ProcessInfo.processInfo.processIdentifier)"
        )
        if shouldTerminate {
            terminate(process)
        }
    }

    public func processTerminated(_ process: Process, phase: String) {
        lock.lock()
        processes[process.processIdentifier] = nil
        lock.unlock()
        record(
            "bottle.create.wine.process.terminated phase=\(phase) pid=\(process.processIdentifier) " +
                "exit_status=\(process.terminationStatus) reason=\(terminationReason(process))"
        )
    }

    public func cancel(reason: String) {
        lock.lock()
        cancellationRequested = true
        let ownedProcesses = Array(processes.values)
        lock.unlock()

        record("bottle.create.wine.cancel.requested reason=\(safeValue(reason)) owned=\(ownedProcesses.count)")
        ownedProcesses.forEach(terminate)
    }

    public func finish() {
        lock.lock()
        completed = true
        let liveProcesses = processes.values.filter(\.isRunning).count
        lock.unlock()
        record("bottle.create.wine.operation.completed live_owned_processes=\(liveProcesses)")
    }

    public var isCompleted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let processIdentifier = process.processIdentifier
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2) {
            guard process.isRunning else { return }
            Darwin.kill(processIdentifier, SIGKILL)
        }
    }

    private func terminationReason(_ process: Process) -> String {
        switch process.terminationReason {
        case .exit:
            return "exit"
        case .uncaughtSignal:
            return "uncaught_signal"
        @unknown default:
            return "unknown"
        }
    }

    private func safeCommand(_ command: [String]) -> String {
        safeValue(command.joined(separator: " "))
    }

    private func safeValue(_ value: String) -> String {
        WineDiagnosticSanitizer.singleLine(WineDiagnosticSanitizer.redact(value))
    }

    private func record(_ detail: String) {
        let message = "\(detail) operation_id=\(id.uuidString) bottle_id=\(bottleIdentifier)"
        Logger.wineKit.notice("\(message, privacy: .public)")
    }
}

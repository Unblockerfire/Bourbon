//
//  BottleVM.swift
//  Whisky
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation
import os
import SemanticVersion
import WhiskyKit

enum BottleCreationDiagnostics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Bourbon",
        category: "bottle-creation"
    )

    static func record(_ event: String) {
        logger.notice("\(event, privacy: .public)")
    }
}

// swiftlint:disable:next todo
// TODO: Don't use unchecked!
@MainActor
final class BottleVM: ObservableObject {
    static let shared = BottleVM()

    var bottlesList = BottleData()
    @Published var bottles: [Bottle] = []
    private var activeCreationOperations: [UUID: BottleWineOperation] = [:]

    @MainActor
    func loadBottles() {
        bottles = bottlesList.loadBottles()
    }

    func countActive() -> Int {
        return bottles.filter { $0.isAvailable == true }.count
    }

    // swiftlint:disable:next function_body_length
    func createNewBottle(bottleName: String, winVersion: WinVersion, bottleURL: URL) async throws -> URL {
        let newBottleDir = bottleURL.appending(path: UUID().uuidString)
        let wineOperation = BottleWineOperation(prefixURL: newBottleDir)
        var createdDirectory = false
        var createdBottle: Bottle?
        activeCreationOperations[wineOperation.id] = wineOperation

        do {
            try await runCreationStage(.directory) {
                try Task.checkCancellation()
                try FileManager.default.createDirectory(at: newBottleDir, withIntermediateDirectories: true)
                createdDirectory = true
                try Task.checkCancellation()
            }

            let bottle = try await runCreationStage(.metadata) {
                let bottle = Bottle(bottleUrl: newBottleDir, inFlight: true)
                bottle.settings.windowsVersion = winVersion
                bottle.settings.name = bottleName
                bottles.append(bottle)
                createdBottle = bottle
                return bottle
            }

            let semanticWineVersion = try await runCreationStage(.wine) {
                try await initializeWine(
                    bottle: bottle,
                    winVersion: winVersion,
                    operation: wineOperation
                )
            }

            try await runCreationStage(.persistence) {
                bottle.settings.wineVersion = semanticWineVersion
                bottle.inFlight = false
                if !bottlesList.paths.contains(newBottleDir) {
                    bottlesList.paths.append(newBottleDir)
                }
            }

            try await runCreationStage(.reload) {
                loadBottles()
            }
            wineOperation.finish()
            activeCreationOperations[wineOperation.id] = nil
            return newBottleDir
        } catch {
            if let createdBottle,
               wineOperation.invocationCount(for: "configuration") > 0 {
                try? await Wine.stopBottleProcesses(
                    bottle: createdBottle,
                    operation: wineOperation,
                    reason: error is CancellationError ? "creation_cancelled" : "creation_failed"
                )
            }
            cleanupPartialBottle(at: newBottleDir, removeDirectory: createdDirectory)
            wineOperation.finish()
            activeCreationOperations[wineOperation.id] = nil
            throw error
        }
    }

    private func initializeWine(
        bottle: Bottle,
        winVersion: WinVersion,
        operation: BottleWineOperation
    ) async throws -> SemanticVersion {
        let runtime: WineRuntimePreflightResult
        do {
            runtime = try await runWineCreationProcess(phase: "preflight") {
                try await Wine.preflightRuntime(operation: operation)
            }
        } catch let error as WineRuntimePreflightError where error.diagnosticCode == "runtime_preflight_timeout" {
            throw BottleWineOperationError.wineInitializationTimeout
        }
        try Task.checkCancellation()
        do {
            _ = try await runWineCreationProcess(phase: "configuration") {
                try await Wine.changeWinVersion(bottle: bottle, win: winVersion, operation: operation)
            }
        } catch is WineCommandTimeoutError {
            throw BottleWineOperationError.wineConfigurationTimeout
        }
        try Task.checkCancellation()
        try await runWineCreationProcess(phase: "settlement") {
            try await Wine.settleBottleCreation(bottle: bottle, operation: operation)
        }
        try Task.checkCancellation()
        guard let semanticWineVersion = WineSemanticVersion.parse(runtime.version) else {
            throw BottleCreationError.invalidWineVersion
        }
        return semanticWineVersion
    }

    func cancelActiveBottleCreations() {
        for operation in activeCreationOperations.values {
            operation.cancel(reason: "application_termination")
        }
    }

    private func runCreationStage<Result>(
        _ stage: BottleCreationStage,
        operation: @MainActor () async throws -> Result
    ) async throws -> Result {
        BottleCreationDiagnostics.record(stage.startedEvent)
        do {
            let result = try await operation()
            if let completedEvent = stage.completedEvent {
                BottleCreationDiagnostics.record(completedEvent)
            }
            return result
        } catch is CancellationError {
            BottleCreationDiagnostics.record("bottle.create.cancel.completed stage=\(stage.rawValue)")
            throw CancellationError()
        } catch {
            let errorType = String(describing: type(of: error))
            let description = safeErrorDescription(error)
            BottleCreationDiagnostics.record(
                "bottle.create.failed stage=\(stage.rawValue) " +
                "error_type=\(errorType) description=\(description)"
            )
            throw error
        }
    }

    private func runWineCreationProcess<Result>(
        phase: String,
        operation: @MainActor () async throws -> Result
    ) async throws -> Result {
        BottleCreationDiagnostics.record("bottle.create.wine.process.started stage=wine phase=\(phase)")
        do {
            let result = try await operation()
            BottleCreationDiagnostics.record(
                "bottle.create.wine.process.terminated stage=wine phase=\(phase) status=success"
            )
            return result
        } catch is CancellationError {
            BottleCreationDiagnostics.record(
                "bottle.create.wine.process.terminated stage=wine phase=\(phase) status=cancelled"
            )
            throw CancellationError()
        } catch {
            let errorType = String(describing: type(of: error))
            let description = safeErrorDescription(error)
            BottleCreationDiagnostics.record(
                "bottle.create.wine.process.terminated stage=wine phase=\(phase) " +
                "status=failure error_type=\(errorType) description=\(description)"
            )
            let gatekeeperBlocked = (error as? WineProcessError)?.isGatekeeperBlocked == true
                || (error as? WineRuntimePreflightError)?.isGatekeeperBlocked == true
            if gatekeeperBlocked {
                BottleCreationDiagnostics.record(
                    "bottle.create.wine.gatekeeper_blocked stage=wine phase=\(phase)"
                )
                throw BottleCreationError.gatekeeperBlocked
            }
            throw error
        }
    }

    private func safeErrorDescription(_ error: Error) -> String {
        if let preflightError = error as? WineRuntimePreflightError {
            return preflightError.unifiedLogDescription
        }
        if let creationError = error as? BottleCreationError {
            switch creationError {
            case .invalidWineVersion: return "invalid_wine_version"
            case .gatekeeperBlocked: return "gatekeeper_blocked"
            }
        }
        if let operationError = error as? BottleWineOperationError {
            return operationError.diagnosticCode
        }
        if let timeoutError = error as? WineCommandTimeoutError {
            return "wine_command_timeout_\(timeoutError.phase)"
        }
        if let wineError = error as? WineProcessError {
            return "wine_process_exit_status_\(wineError.status)"
        }
        if error is WineVersionError {
            return "wine_version_output_invalid"
        }
        if error is CocoaError {
            return "filesystem_operation_failed"
        }
        return "creation_operation_failed"
    }

    private func cleanupPartialBottle(at bottleURL: URL, removeDirectory: Bool) {
        bottles.removeAll { $0.url == bottleURL }
        bottlesList.paths.removeAll { $0 == bottleURL }
        guard removeDirectory else { return }

        do {
            try FileManager.default.removeItem(at: bottleURL)
        } catch {
            let errorType = String(describing: type(of: error))
            BottleCreationDiagnostics.record(
                "bottle.create.cleanup.failed stage=cleanup error_type=\(errorType) " +
                "description=partial_directory_removal_failed"
            )
        }
    }
}

enum BottleCreationError: LocalizedError {
    case invalidWineVersion
    case gatekeeperBlocked

    var errorDescription: String? {
        switch self {
        case .invalidWineVersion:
            return "BourbonWine returned an invalid Wine version."
        case .gatekeeperBlocked:
            return "macOS blocked a BourbonWine component while creating this Bottle. " +
                "Approve BourbonWine in Privacy & Security, then try again."
        }
    }
}

private enum BottleCreationStage: String {
    case directory
    case metadata
    case wine
    case persistence
    case reload

    var startedEvent: String {
        "bottle.create.\(rawValue).started"
    }

    var completedEvent: String? {
        switch self {
        case .wine:
            return nil
        default:
            return "bottle.create.\(rawValue).completed"
        }
    }
}

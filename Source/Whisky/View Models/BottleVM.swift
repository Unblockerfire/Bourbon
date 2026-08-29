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

    @MainActor
    func loadBottles() {
        bottles = bottlesList.loadBottles()
    }

    func countActive() -> Int {
        return bottles.filter { $0.isAvailable == true }.count
    }

    func createNewBottle(bottleName: String, winVersion: WinVersion, bottleURL: URL) async throws -> URL {
        let newBottleDir = bottleURL.appending(path: UUID().uuidString)
        var createdDirectory = false

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
                return bottle
            }

            let semanticWineVersion = try await runCreationStage(.wine) {
                try await initializeWine(bottle: bottle, winVersion: winVersion)
            }

            try await runCreationStage(.persistence) {
                bottle.settings.wineVersion = semanticWineVersion
                bottle.inFlight = false
                bottlesList.paths.append(newBottleDir)
            }

            try await runCreationStage(.reload) {
                loadBottles()
            }
            return newBottleDir
        } catch {
            cleanupPartialBottle(at: newBottleDir, removeDirectory: createdDirectory)
            throw error
        }
    }

    private func initializeWine(bottle: Bottle, winVersion: WinVersion) async throws -> SemanticVersion {
        let runtime = try await runWineCreationProcess(phase: "preflight") {
            try await Wine.preflightRuntime()
        }
        try Task.checkCancellation()
        _ = try await runWineCreationProcess(phase: "configuration") {
            try await Wine.changeWinVersion(bottle: bottle, win: winVersion)
        }
        try Task.checkCancellation()
        guard let semanticWineVersion = WineSemanticVersion.parse(runtime.version) else {
            throw BottleCreationError.invalidWineVersion
        }
        return semanticWineVersion
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
            throw error
        }
    }

    private func safeErrorDescription(_ error: Error) -> String {
        if error is BottleCreationError {
            return "invalid_wine_version"
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

enum BottleCreationError: Error {
    case invalidWineVersion
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

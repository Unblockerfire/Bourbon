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

struct BottleCreationFailure: LocalizedError {
    let stage: String
    let phase: String?
    let diagnosticCode: String
    let exitStatus: Int32?
    let outputExcerpt: String?
    let cleanupStatus: String?

    var errorDescription: String? {
        userMessage
    }

    var userMessage: String {
        switch stage {
        case "directory":
            return "Bottle creation failed while preparing storage."
        case "metadata":
            return "Bottle creation failed while saving its initial settings."
        case "wine":
            return "Bottle creation failed during runtime initialization."
        case "persistence":
            return "Bottle creation failed while saving the bottle."
        case "reload":
            return "Bottle creation failed while loading the new bottle."
        default:
            return "Bourbon couldn’t create this bottle."
        }
    }

    var diagnosticDetails: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        let runtimeVersion = WhiskyWineInstaller.whiskyWineVersion().map(String.init(describing:)) ?? "unknown"
        let winePath = Wine.wineBinary.path(percentEncoded: false)
        let wineserverPath = WhiskyWineInstaller.binFolder.appending(path: "wineserver").path(percentEncoded: false)
        let fileManager = FileManager.default
        let phaseLine = phase.map { "Phase: \($0)\n" } ?? ""
        let statusLine = exitStatus.map { "Wine exit status: \($0)\n" } ?? ""
        let cleanupLine = cleanupStatus.map { "Partial bottle cleanup: \($0)\n" } ?? ""
        let outputLine = outputExcerpt.map { "\nSafe Wine output excerpt:\n\($0)" } ?? ""

        return """
        Bourbon: \(version) (\(build))
        Stage: \(stage)
        \(phaseLine)Diagnostic code: \(diagnosticCode)
        \(statusLine)Runtime version: \(runtimeVersion)
        Rosetta installed: \(Rosetta2.isRosettaInstalled)
        Wine launcher exists: \(fileManager.fileExists(atPath: winePath))
        Wine launcher executable: \(fileManager.isExecutableFile(atPath: winePath))
        Wineserver exists: \(fileManager.fileExists(atPath: wineserverPath))
        Wineserver executable: \(fileManager.isExecutableFile(atPath: wineserverPath))
        \(cleanupLine)Logs: ~/Library/Logs/\(Bundle.whiskyBundleIdentifier)
        \(outputLine)
        """
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func recordingCleanup(_ status: String) -> BottleCreationFailure {
        BottleCreationFailure(
            stage: stage,
            phase: phase,
            diagnosticCode: diagnosticCode,
            exitStatus: exitStatus,
            outputExcerpt: outputExcerpt,
            cleanupStatus: status
        )
    }

    static func make(error: Error, stage: BottleCreationStage, phase: String? = nil) -> BottleCreationFailure {
        if let failure = error as? BottleCreationFailure {
            return failure
        }

        if let wineError = error as? WineProcessError {
            return BottleCreationFailure(
                stage: stage.rawValue,
                phase: phase,
                diagnosticCode: "wine_process_exit_status_\(wineError.status)",
                exitStatus: wineError.status,
                outputExcerpt: safeOutputExcerpt(wineError.output),
                cleanupStatus: nil
            )
        }

        let diagnosticCode: String
        if error is BottleCreationError {
            diagnosticCode = "invalid_wine_version"
        } else if error is WineVersionError {
            diagnosticCode = "wine_version_output_invalid"
        } else {
            let nsError = error as NSError
            diagnosticCode = "foundation_error_\(safeDomain(nsError.domain))_code_\(nsError.code)"
        }

        return BottleCreationFailure(
            stage: stage.rawValue,
            phase: phase,
            diagnosticCode: diagnosticCode,
            exitStatus: nil,
            outputExcerpt: nil,
            cleanupStatus: nil
        )
    }

    private static func safeOutputExcerpt(_ output: String) -> String? {
        let normalized = output
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return String(BourbonRedactor.redact(normalized).suffix(2_000))
    }

    private static func safeDomain(_ domain: String) -> String {
        let safeScalars = domain.lowercased().unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "_"
        }
        return String(safeScalars)
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
            let cleanupStatus = cleanupPartialBottle(at: newBottleDir, removeDirectory: createdDirectory)
            if let failure = error as? BottleCreationFailure {
                throw failure.recordingCleanup(cleanupStatus)
            }
            throw error
        }
    }

    private func initializeWine(bottle: Bottle, winVersion: WinVersion) async throws -> SemanticVersion {
        _ = try await runWineCreationProcess(phase: "configuration") {
            try await Wine.changeWinVersion(bottle: bottle, win: winVersion)
        }
        try Task.checkCancellation()
        let wineVersion = try await runWineCreationProcess(phase: "version") {
            try await Wine.wineVersion()
        }
        try Task.checkCancellation()
        guard let semanticWineVersion = WineSemanticVersion.parse(wineVersion) else {
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
            let failure = BottleCreationFailure.make(error: error, stage: stage)
            BottleCreationDiagnostics.record(
                "bottle.create.failed stage=\(stage.rawValue) " +
                "description=\(failure.diagnosticCode)"
            )
            throw failure
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
            let failure = BottleCreationFailure.make(error: error, stage: .wine, phase: phase)
            BottleCreationDiagnostics.record(
                "bottle.create.wine.process.terminated stage=wine phase=\(phase) " +
                "status=failure description=\(failure.diagnosticCode)"
            )
            throw failure
        }
    }

    private func cleanupPartialBottle(at bottleURL: URL, removeDirectory: Bool) -> String {
        bottles.removeAll { $0.url == bottleURL }
        bottlesList.paths.removeAll { $0 == bottleURL }
        guard removeDirectory else { return "not_needed" }

        do {
            try FileManager.default.removeItem(at: bottleURL)
            return "completed"
        } catch {
            let nsError = error as NSError
            BottleCreationDiagnostics.record(
                "bottle.create.cleanup.failed stage=cleanup " +
                "description=partial_directory_removal_failed code=\(nsError.code)"
            )
            return "failed_code_\(nsError.code)"
        }
    }
}

enum BottleCreationError: Error {
    case invalidWineVersion
}

enum BottleCreationStage: String {
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

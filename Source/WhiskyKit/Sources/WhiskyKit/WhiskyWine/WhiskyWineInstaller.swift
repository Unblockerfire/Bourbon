//
//  WhiskyWineInstaller.swift
//  WhiskyKit
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

// swiftlint:disable file_length

import Foundation
import SemanticVersion
import os.log
import CryptoKit

// swiftlint:disable:next type_body_length
public class WhiskyWineInstaller {
    public static let archiveURLDefaultsKey = "whiskyWineArchiveURL"
    public static let versionURLDefaultsKey = "whiskyWineVersionURL"
    public static let defaultArchiveURLString = [
        "https://github.com/Unblockerfire/Whisky/releases/download",
        "bourbon-runtime-1.0.0",
        "BourbonWine-1.0.0-macOS-x86_64.tar.gz"
    ].joined(separator: "/")
    public static let defaultVersionURLString = [
        "https://github.com/Unblockerfire/Whisky/releases/download",
        "bourbon-runtime-1.0.0",
        "BourbonWineVersion.plist"
    ].joined(separator: "/")

    public static let runtimeAPIBaseURLDefaultsKey = "bourbonRuntimeAPIBaseURL"
    public static let defaultRuntimeAPIBaseURLString = "https://api.getbourbon.app"

    public static var archiveURL: URL {
        configuredURL(forKey: archiveURLDefaultsKey, defaultValue: defaultArchiveURLString)
    }

    private static var versionURL: URL {
        configuredURL(forKey: versionURLDefaultsKey, defaultValue: defaultVersionURLString)
    }

    private static var runtimeAPIBaseURL: URL {
        configuredURL(forKey: runtimeAPIBaseURLDefaultsKey, defaultValue: defaultRuntimeAPIBaseURLString)
    }

    public struct BourbonRuntimeInfo: Codable, Sendable {
        public let version: String
        public let wineVersion: String
        public let archiveName: String
        public let sha256: String
        public let plistUrl: URL
        public let archiveUrl: URL
        public let expiresInSeconds: Int
    }

    public struct BundledDiagnosticRuntimeInfo: Codable, Sendable, Equatable {
        public let runtimeVersion: String
        public let wineVersion: String
        public let sourceRepository: String
        public let sourceRelease: String
        public let sourceAsset: String
        public let sourceAssetSHA256: String
        public let maximumMinimumMacOS: String
    }

    public static func bundledDiagnosticRuntime(
        in bundle: Bundle = .main
    ) -> (archive: URL, info: BundledDiagnosticRuntimeInfo)? {
        guard let archive = bundle.url(
            forResource: "BourbonWineDiagnosticRuntime",
            withExtension: "tar.gz"
        ), let metadata = bundle.url(
            forResource: "BourbonWineDiagnosticRuntime",
            withExtension: "json"
        ) else {
            return nil
        }

        recordRuntimeEvent(
            "runtime.bundle.archive.found",
            detail: "resource=\(archive.lastPathComponent)"
        )

        do {
            let data = try Data(contentsOf: metadata)
            let info = try JSONDecoder().decode(BundledDiagnosticRuntimeInfo.self, from: data)
            guard SemanticVersion(info.runtimeVersion) != nil else {
                Logger.wineKit.error("Bundled diagnostic runtime has an invalid version.")
                return nil
            }
            recordRuntimeEvent(
                "runtime.bundle.manifest.loaded",
                detail: "runtime_version=\(info.runtimeVersion) wine_version=\(info.wineVersion)"
            )
            return (archive, info)
        } catch {
            Logger.wineKit.error("Failed to read bundled diagnostic runtime metadata: \(error)")
            return nil
        }
    }

    /// Installs the runtime embedded in a diagnostic Bourbon app. The archive is
    /// first copied out of the read-only app bundle, so installation retains the
    /// same transactional staging and rollback behavior as a downloaded archive.
    public static func installBundledDiagnosticRuntime(
        in bundle: Bundle = .main,
        into destinationApplicationFolder: URL = applicationFolder
    ) throws -> String {
        guard let bundledRuntime = bundledDiagnosticRuntime(in: bundle) else {
            throw WhiskyWineInstallerError.missingBundledDiagnosticRuntime
        }

        recordRuntimeEvent(
            "runtime.install.required",
            detail: "runtime_version=\(bundledRuntime.info.runtimeVersion)"
        )
        recordRuntimeEvent(
            "runtime.install.destination",
            detail: "path=\(WineDiagnosticSanitizer.redact(destinationApplicationFolder.path))"
        )

        recordUpdateEvent("runtime.update.download.started", detail: "source=bundled_diagnostic_runtime")
        let archive = try persistLocalArchive(at: bundledRuntime.archive)
        recordUpdateEvent("runtime.update.download.completed", detail: "source=bundled_diagnostic_runtime")
        recordUpdateEvent("runtime.update.verification.started")
        try validateArchive(at: archive, sourceURL: nil)
        recordUpdateEvent("runtime.update.verification.completed")
        try install(
            from: archive,
            runtimeVersion: bundledRuntime.info.runtimeVersion,
            into: destinationApplicationFolder
        )
        return bundledRuntime.info.runtimeVersion
    }

    /// Updates from the diagnostic archive when it is packaged in this app;
    /// production builds use the runtime manifest's signed/checksummed archive.
    public static func installLatestRuntimeUpdate(
        in bundle: Bundle = .main,
        into destinationApplicationFolder: URL = applicationFolder
    ) async throws -> String {
        if bundledDiagnosticRuntime(in: bundle) != nil {
            return try await Task.detached(priority: .userInitiated) {
                try installBundledDiagnosticRuntime(in: bundle, into: destinationApplicationFolder)
            }.value
        }

        let runtimeInfo = try await latestRuntimeInfo()
        guard SemanticVersion(runtimeInfo.version) != nil else {
            throw WhiskyWineInstallerError.invalidRuntimeVersion(runtimeInfo.version)
        }

        recordUpdateEvent("runtime.update.download.started", detail: "source=runtime_manifest")
        recordUpdateEvent("runtime.update.download.progress", detail: "percent=0")
        let request = URLRequest(url: runtimeInfo.archiveUrl)
        let (temporaryURL, response) = try await URLSession(configuration: .ephemeral).download(for: request)
        let archive = try persistDownloadedArchive(
            at: temporaryURL,
            response: response,
            sourceURL: runtimeInfo.archiveUrl
        )
        recordUpdateEvent("runtime.update.download.progress", detail: "percent=100")
        recordUpdateEvent("runtime.update.download.completed", detail: "source=runtime_manifest")
        recordUpdateEvent("runtime.update.verification.started")
        try validateArchiveSHA256(at: archive, expected: runtimeInfo.sha256)
        recordUpdateEvent("runtime.update.verification.completed")
        try await Task.detached(priority: .userInitiated) {
            try install(from: archive, runtimeVersion: runtimeInfo.version, into: destinationApplicationFolder)
        }.value
        return runtimeInfo.version
    }

    /// Logs user-visible update lifecycle markers without emitting private paths
    /// or network credentials into the diagnostic log.
    public static func recordUpdateEvent(_ event: String, detail: String? = nil) {
        let safeDetail = detail?.replacingOccurrences(of: "\n", with: " ") ?? ""
        if safeDetail.isEmpty {
            Logger.wineKit.notice("\(event, privacy: .public)")
            print(event)
        } else {
            Logger.wineKit.notice("\(event, privacy: .public) \(safeDetail, privacy: .public)")
            print("\(event) \(safeDetail)")
        }
    }

    public static func recordRuntimeEvent(_ event: String, detail: String? = nil) {
        recordUpdateEvent(event, detail: detail)
    }

    public static func latestRuntimeInfo() async throws -> BourbonRuntimeInfo {
        let request = URLRequest(url: runtimeAPIBaseURL.appending(path: "runtime/latest"))
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        try validateVersionResponse(response, sourceURL: request.url ?? runtimeAPIBaseURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(BourbonRuntimeInfo.self, from: data)
    }

    /// The Whisky application folder
    public static let applicationFolder = applicationFolder(
        bundleIdentifier: Bundle.whiskyBundleIdentifier
    )

    public static func applicationFolder(
        bundleIdentifier: String,
        applicationSupportRoot: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
    ) -> URL {
        applicationSupportRoot.appending(path: bundleIdentifier)
    }

    /// The folder of all the libfrary files
    public static let libraryFolder = applicationFolder.appending(path: "Libraries")

    /// URL to the installed `wine` `bin` directory
    public static let binFolder: URL = libraryFolder.appending(path: "Wine").appending(path: "bin")

    /// A single retained runtime copy used only for a safe, user-initiated recovery.
    /// It is a sibling of `Libraries` so its marker and manifest stay together.
    public static let previousLibraryFolder: URL = applicationFolder.appending(path: "Libraries.previous")

    public static func isWhiskyWineInstalled() -> Bool {
        runtimeReadiness(in: applicationFolder).isReady
    }

    public static func runtimeBinariesInstalled() -> Bool {
        runtimeReadiness(in: applicationFolder).hasRequiredFiles
    }

    public static func previousRuntimeReadiness(
        in applicationFolder: URL = applicationFolder
    ) -> RuntimeReadiness {
        RuntimeReadiness.validate(
            applicationFolder: applicationFolder,
            librariesFolder: applicationFolder.appending(path: "Libraries.previous"),
            runWineVersion: false
        )
    }

    public static func hasRestorablePreviousRuntime(
        in applicationFolder: URL = applicationFolder
    ) -> Bool {
        previousRuntimeReadiness(in: applicationFolder).isReady
    }

    /// The only authoritative statement that a runtime is ready.  A version marker is
    /// deliberately not sufficient: it is written last and is checked against the
    /// manifest shipped inside the runtime itself.
    public static func runtimeReadiness(in applicationFolder: URL) -> RuntimeReadiness {
        RuntimeReadiness.validate(applicationFolder: applicationFolder)
    }

    /// Discovers an existing runtime without equating a failed preflight with a
    /// missing installation. In particular, Gatekeeper approval is recoverable
    /// and must never cause a replacement download on the next launch.
    public static func discoverRuntime(
        in applicationFolder: URL = applicationFolder,
        expectedRuntimeVersion: String? = nil
    ) async -> RuntimeDiscovery {
        recordRuntimeEvent("runtime.discovery.started")
        let requiredRuntimeVersion = expectedRuntimeVersion ?? bundledDiagnosticRuntime()?.info.runtimeVersion
        let fileManager = FileManager.default
        let wineRoot = applicationFolder.appending(path: "Libraries/Wine")
        guard fileManager.fileExists(atPath: wineRoot.path) else {
            recordRuntimeEvent("runtime.discovery.missing")
            return RuntimeDiscovery(state: .missing)
        }

        recordRuntimeEvent("runtime.discovery.found")
        let files = RuntimeReadiness.validate(
            applicationFolder: applicationFolder,
            expectedRuntimeVersion: requiredRuntimeVersion,
            runWineVersion: false
        )
        if let discovery = discoveryForInvalidFiles(files) { return discovery }

        recordRuntimeEvent("runtime.discovery.valid")
        do {
            let result = try await Wine.preflightRuntime(
                executableURL: applicationFolder.appending(path: "Libraries/Wine/bin/wine")
            )
            recordRuntimeEvent(
                "runtime.discovery.ready",
                detail: "wine_version=\(result.version)"
            )
            return RuntimeDiscovery(
                state: .ready,
                readiness: files,
                wineVersion: result.version
            )
        } catch let error as WineRuntimePreflightError where error.isGatekeeperBlocked {
            recordRuntimeEvent("runtime.discovery.gatekeeper_blocked")
            return RuntimeDiscovery(
                state: .gatekeeperBlocked,
                readiness: files,
                errorDescription: error.localizedDescription
            )
        } catch {
            recordRuntimeEvent(
                "runtime.discovery.valid",
                detail: "state=verification_failed error=" +
                    WineDiagnosticSanitizer.singleLine(error.localizedDescription)
            )
            return RuntimeDiscovery(
                state: .verificationFailed,
                readiness: files,
                errorDescription: error.localizedDescription
            )
        }
    }

    private static func discoveryForInvalidFiles(_ files: RuntimeReadiness) -> RuntimeDiscovery? {
        guard !files.isReady else { return nil }
        let state: RuntimeDiscovery.State
        if files.failures.contains("runtime_version_mismatch") {
            state = .unsupported
        } else if files.failures.contains(where: {
            $0.hasPrefix("missing:") || $0.hasPrefix("not_executable:")
        }) {
            state = .corruptOrIncomplete
        } else {
            state = .verificationFailed
        }
        let event = state == .corruptOrIncomplete
            ? "runtime.discovery.incomplete"
            : "runtime.discovery.valid"
        recordRuntimeEvent(
            event,
            detail: "state=\(state.rawValue) failures=\(files.failures.joined(separator: ","))"
        )
        return RuntimeDiscovery(state: state, readiness: files)
    }

    /// Re-checks an existing runtime after the user approves Wine in macOS
    /// Privacy & Security. This never downloads, extracts, or replaces files.
    public static func retryInstalledRuntimeReadiness(
        in applicationFolder: URL = applicationFolder
    ) async throws -> WineRuntimePreflightResult {
        recordRuntimeEvent("runtime.retry.started")
        let files = RuntimeReadiness.validate(
            applicationFolder: applicationFolder,
            runWineVersion: false
        )
        guard files.isReady else {
            recordRuntimeEvent(
                "runtime.retry.failed",
                detail: "stage=files failures=\(files.failures.joined(separator: ","))"
            )
            throw WhiskyWineInstallerError.runtimeNotReady(files)
        }
        recordRuntimeEvent("runtime.retry.files_verified")
        recordRuntimeEvent("runtime.retry.preflight.started")
        do {
            let result = try await Wine.preflightRuntime(
                executableURL: applicationFolder.appending(path: "Libraries/Wine/bin/wine")
            )
            recordRuntimeEvent("runtime.retry.preflight.succeeded")
            return result
        } catch let error as WineRuntimePreflightError where error.isGatekeeperBlocked {
            recordRuntimeEvent("runtime.retry.preflight.blocked")
            throw error
        } catch {
            recordRuntimeEvent(
                "runtime.retry.failed",
                detail: "stage=preflight error=\(WineDiagnosticSanitizer.singleLine(error.localizedDescription))"
            )
            throw error
        }
    }

    /// Atomically promotes the one retained previous runtime back into use. The
    /// caller still performs the normal bounded Wine preflight afterward.
    public static func restorePreviousRuntime(
        in destinationApplicationFolder: URL = applicationFolder
    ) throws {
        let fileManager = FileManager.default
        let current = destinationApplicationFolder.appending(path: "Libraries")
        let previous = destinationApplicationFolder.appending(path: "Libraries.previous")
        let recovered = destinationApplicationFolder.appending(path: ".BourbonWineRestore-\(UUID().uuidString)")
        let readiness = RuntimeReadiness.validate(
            applicationFolder: destinationApplicationFolder,
            librariesFolder: previous,
            runWineVersion: false
        )
        guard readiness.isReady else { throw WhiskyWineInstallerError.runtimeNotReady(readiness) }

        recordRuntimeEvent("runtime.rollback.started", detail: "purpose=restore_previous")
        do {
            if fileManager.fileExists(atPath: current.path) {
                try fileManager.moveItem(at: current, to: recovered)
            }
            try fileManager.moveItem(at: previous, to: current)
            let installed = RuntimeReadiness.validate(
                applicationFolder: destinationApplicationFolder,
                runWineVersion: false
            )
            guard installed.isReady else { throw WhiskyWineInstallerError.runtimeNotReady(installed) }
            if fileManager.fileExists(atPath: recovered.path) {
                try fileManager.moveItem(at: recovered, to: previous)
            }
            recordRuntimeEvent("runtime.rollback.succeeded", detail: "purpose=restore_previous")
        } catch {
            if fileManager.fileExists(atPath: current.path) {
                try? fileManager.removeItem(at: current)
            }
            if fileManager.fileExists(atPath: recovered.path) {
                try? fileManager.moveItem(at: recovered, to: current)
            }
            throw error
        }
    }

    public static func legacyRuntimeMarkerURL() -> URL? {
        for name in ["whiskyWineVersion", "GPTKVersion"] {
            let versionPlist = libraryFolder
                .appending(path: name)
                .appendingPathExtension("plist")
            if FileManager.default.fileExists(atPath: versionPlist.path(percentEncoded: false)) {
                return versionPlist
            }
        }
        return nil
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public static func install(
        from: URL,
        runtimeVersion: String? = nil,
        into destinationApplicationFolder: URL = applicationFolder
    ) throws {
        let fileManager = FileManager.default
        let destinationLibraryFolder = destinationApplicationFolder.appending(path: "Libraries")
        var stagingRoot: URL?
        var backupLibraryFolder: URL?
        defer {
            if let stagingRoot {
                try? fileManager.removeItem(at: stagingRoot)
            }
        }

        do {
            recordRuntimeEvent("runtime.install.started")
            try validateArchive(at: from, sourceURL: nil)
            recordRuntimeEvent(
                "runtime.install.destination",
                detail: "path=\(WineDiagnosticSanitizer.redact(destinationApplicationFolder.path))"
            )

            if !fileManager.fileExists(atPath: destinationApplicationFolder.path) {
                try fileManager.createDirectory(at: destinationApplicationFolder, withIntermediateDirectories: true)
            }

            let staging = destinationApplicationFolder.appending(path: ".BourbonWineInstall-\(UUID().uuidString)")
            stagingRoot = staging
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            recordUpdateEvent("runtime.update.extraction.started")
            recordRuntimeEvent("runtime.extract.started")
            do {
                try Tar.untar(tarBall: from, toURL: staging)
            } catch {
                let safeError = WineDiagnosticSanitizer.singleLine(error.localizedDescription)
                recordRuntimeEvent("runtime.extract.failed", detail: "error=\(safeError)")
                throw error
            }
            recordRuntimeEvent("runtime.extract.completed")
            recordUpdateEvent("runtime.update.extraction.completed")

            let stagedReadiness = RuntimeReadiness.validate(
                applicationFolder: staging,
                expectedRuntimeVersion: runtimeVersion,
                requireVersionMarker: false
            )
            guard stagedReadiness.isReady else {
                let failures = stagedReadiness.failures
                    .map(WineDiagnosticSanitizer.redact)
                    .joined(separator: ",")
                recordRuntimeEvent(
                    "runtime.extract.failed",
                    detail: "check=staging_readiness failures=\(failures)"
                )
                throw WhiskyWineInstallerError.runtimeNotReady(stagedReadiness)
            }

            let existingReadiness = RuntimeReadiness.validate(
                applicationFolder: destinationApplicationFolder
            )
            let preserveExistingRuntime = existingReadiness.isReady
            if fileManager.fileExists(atPath: destinationLibraryFolder.path(percentEncoded: false)) {
                let backup = destinationApplicationFolder.appending(path: ".BourbonWineBackup-\(UUID().uuidString)")
                backupLibraryFolder = backup
                try fileManager.moveItem(at: destinationLibraryFolder, to: backup)
            }

            do {
                recordUpdateEvent("runtime.update.install.started")
                try fileManager.moveItem(at: staging.appending(path: "Libraries"), to: destinationLibraryFolder)
                try writeInstalledVersionMarkerIfNeeded(runtimeVersion: runtimeVersion, in: destinationLibraryFolder)
                recordUpdateEvent("runtime.update.preflight.started")
                recordRuntimeEvent("runtime.preflight.started", detail: "purpose=runtime_install")
                let installedReadiness = RuntimeReadiness.validate(
                    applicationFolder: destinationApplicationFolder,
                    expectedRuntimeVersion: runtimeVersion,
                    runWineVersion: false
                )
                guard installedReadiness.isReady else {
                    throw WhiskyWineInstallerError.runtimeNotReady(installedReadiness)
                }
                recordUpdateEvent("runtime.update.preflight.completed")
                recordRuntimeEvent("runtime.preflight.completed", detail: "purpose=runtime_install")
                recordUpdateEvent("runtime.update.install.completed")
                recordRuntimeEvent("runtime.install.completed")
            } catch {
                if fileManager.fileExists(atPath: destinationLibraryFolder.path(percentEncoded: false)) {
                    try? fileManager.removeItem(at: destinationLibraryFolder)
                }
                if let backupLibraryFolder,
                   fileManager.fileExists(atPath: backupLibraryFolder.path(percentEncoded: false)) {
                    recordRuntimeEvent("runtime.rollback.started", detail: "purpose=failed_replacement")
                    try? fileManager.moveItem(at: backupLibraryFolder, to: destinationLibraryFolder)
                    recordRuntimeEvent("runtime.rollback.succeeded", detail: "purpose=failed_replacement")
                }
                throw error
            }

            if let backupLibraryFolder,
               fileManager.fileExists(atPath: backupLibraryFolder.path(percentEncoded: false)) {
                if preserveExistingRuntime {
                    let previousLibraryFolder = destinationApplicationFolder.appending(path: "Libraries.previous")
                    if fileManager.fileExists(atPath: previousLibraryFolder.path(percentEncoded: false)) {
                        try fileManager.removeItem(at: previousLibraryFolder)
                    }
                    try fileManager.moveItem(at: backupLibraryFolder, to: previousLibraryFolder)
                    recordRuntimeEvent("runtime.backup.created", detail: "purpose=runtime_replacement")
                } else {
                    try fileManager.removeItem(at: backupLibraryFolder)
                }
            }
            // Keep the saved archive available while a user completes any
            // Gatekeeper approval and for the separate manual-recovery path.
        } catch {
            recordRuntimeEvent(
                "runtime.install.failed",
                detail: "error=\(WineDiagnosticSanitizer.singleLine(error.localizedDescription))"
            )
            Logger.wineKit.error("Failed to install BourbonWine from `\(from.path)`: \(error)")
            throw error
        }
    }

    public static func persistDownloadedArchive(
        at temporaryURL: URL,
        response: URLResponse?,
        sourceURL: URL
    ) throws -> URL {
        Logger.wineKit.info(
            "Received BourbonWine download from `\(sourceURL.absoluteString)` at `\(temporaryURL.path)`"
        )

        try validateDownloadResponse(response, sourceURL: sourceURL)
        try validateArchive(at: temporaryURL, sourceURL: sourceURL)

        let savedURL = FileManager.default.temporaryDirectory
            .appending(path: "WhiskyWine-\(UUID().uuidString)")
            .appendingPathExtension("tar.gz")

        if FileManager.default.fileExists(atPath: savedURL.path) {
            try FileManager.default.removeItem(at: savedURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: savedURL)

        Logger.wineKit.info(
            "Downloaded BourbonWine from `\(sourceURL.absoluteString)` to `\(savedURL.path(percentEncoded: false))`"
        )
        return savedURL
    }

    public static func persistLocalArchive(at url: URL) throws -> URL {
        try validateArchive(at: url, sourceURL: nil)

        let savedURL = FileManager.default.temporaryDirectory
            .appending(path: "WhiskyWine-\(UUID().uuidString)")
            .appendingPathExtension("tar.gz")

        if FileManager.default.fileExists(atPath: savedURL.path) {
            try FileManager.default.removeItem(at: savedURL)
        }
        try FileManager.default.copyItem(at: url, to: savedURL)

        Logger.wineKit.info(
            "Using local BourbonWine archive `\(url.path(percentEncoded: false))` copied to `\(savedURL.path)`"
        )
        return savedURL
    }

    public static func uninstall() {
        do {
            try FileManager.default.removeItem(at: libraryFolder)
        } catch {
            print("Failed to uninstall BourbonWine: \(error)")
        }
    }

    public static func shouldUpdateWhiskyWine() async -> (Bool, SemanticVersion) {
        let localVersion = whiskyWineVersion()
        if let bundledRuntime = bundledDiagnosticRuntime(),
           let bundledVersion = SemanticVersion(bundledRuntime.info.runtimeVersion) {
            if let localVersion {
                if localVersion < bundledVersion {
                    return (true, bundledVersion)
                }
            } else {
                return (true, bundledVersion)
            }
        }

        let remoteVersion = await remotewhiskyWineVersion()

        if let localVersion = localVersion, let remoteVersion = remoteVersion {
            if localVersion < remoteVersion {
                return (true, remoteVersion)
            }
        }

        return (false, SemanticVersion(0, 0, 0))
    }

    public static func whiskyWineVersion() -> SemanticVersion? {
        whiskyWineVersion(in: applicationFolder)
    }

    public static func whiskyWineVersion(in applicationFolder: URL) -> SemanticVersion? {
        guard let versionPlist = installedVersionPlistURL(in: applicationFolder) else {
            return nil
        }

        do {
            let decoder = PropertyListDecoder()
            let data = try Data(contentsOf: versionPlist)
            let info = try decoder.decode(WhiskyWineVersionInfo.self, from: data)
            return info.version
        } catch {
            Logger.wineKit.error("Failed to read BourbonWine version plist `\(versionPlist.path)`: \(error)")
            return nil
        }
    }

    private static func installedVersionPlistURL(in applicationFolder: URL) -> URL? {
        let libraryFolder = applicationFolder.appending(path: "Libraries")
        for name in ["BourbonWineVersion", "whiskyWineVersion", "GPTKVersion"] {
            let versionPlist = libraryFolder
                .appending(path: name)
                .appendingPathExtension("plist")
            if FileManager.default.fileExists(atPath: versionPlist.path(percentEncoded: false)) {
                return versionPlist
            }
        }
        return nil
    }

    private static func writeInstalledVersionMarkerIfNeeded(runtimeVersion: String?, in libraryFolder: URL) throws {
        let marker = libraryFolder
            .appending(path: "BourbonWineVersion")
            .appendingPathExtension("plist")

        guard let runtimeVersion,
              SemanticVersion(runtimeVersion) != nil else {
            return
        }

        guard let data = try installedVersionMarkerData(runtimeVersion: runtimeVersion) else {
            return
        }
        try data.write(to: marker, options: .atomic)
    }

    static func installedVersionMarkerData(runtimeVersion: String?) throws -> Data? {
        guard let runtimeVersion,
              let semanticVersion = SemanticVersion(runtimeVersion) else {
            return nil
        }

        return try PropertyListEncoder().encode(WhiskyWineVersionInfo(version: semanticVersion))
    }

    private static func remotewhiskyWineVersion() async -> SemanticVersion? {
        do {
            let runtimeInfo = try await latestRuntimeInfo()
            if let version = SemanticVersion(runtimeInfo.version) {
                return version
            }

            let request = URLRequest(url: runtimeInfo.plistUrl)
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            try validateVersionResponse(response, sourceURL: runtimeInfo.plistUrl)

            let decoder = PropertyListDecoder()
            let remoteInfo = try decoder.decode(WhiskyWineVersionInfo.self, from: data)
            return remoteInfo.version
        } catch {
            Logger.wineKit.warning("Failed to load remote BourbonWine version from `\(versionURL)`: \(error)")
            return nil
        }
    }

    private static func configuredURL(forKey key: String, defaultValue: String) -> URL {
        let string = UserDefaults.standard.string(forKey: key) ?? defaultValue
        if let url = URL(string: string) {
            return url
        }

        Logger.wineKit.error("Invalid BourbonWine URL configured for `\(key)`: \(string)")
        return URL(string: defaultValue) ?? URL(fileURLWithPath: "/")
    }

    private static func validateDownloadResponse(_ response: URLResponse?, sourceURL: URL) throws {
        guard let response = response as? HTTPURLResponse else {
            throw WhiskyWineInstallerError.missingHTTPResponse(sourceURL)
        }

        guard 200..<300 ~= response.statusCode else {
            throw WhiskyWineInstallerError.badHTTPStatus(sourceURL, response.statusCode)
        }

        let contentType = response.value(forHTTPHeaderField: "Content-Type")
        guard !isKnownNonArchiveContentType(contentType) else {
            throw WhiskyWineInstallerError.invalidContentType(sourceURL, contentType ?? "unknown")
        }
    }

    private static func validateVersionResponse(_ response: URLResponse?, sourceURL: URL) throws {
        guard let response = response as? HTTPURLResponse else {
            throw WhiskyWineInstallerError.missingHTTPResponse(sourceURL)
        }

        guard 200..<300 ~= response.statusCode else {
            throw WhiskyWineInstallerError.badHTTPStatus(sourceURL, response.statusCode)
        }
    }

    private static func validateArchive(at url: URL, sourceURL: URL?) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        let header = try handle.read(upToCount: 2) ?? Data()
        guard header == Data([0x1f, 0x8b]) else {
            throw WhiskyWineInstallerError.invalidArchive(sourceURL, url, nil)
        }

        do {
            let entries = try Tar.list(tarBall: url)
            guard entries.contains(where: isLibrariesRootEntry) else {
                throw WhiskyWineInstallerError.invalidArchiveLayout(sourceURL, url)
            }
        } catch let error as WhiskyWineInstallerError {
            throw error
        } catch {
            throw WhiskyWineInstallerError.invalidArchive(sourceURL, url, String(describing: error))
        }
    }

    private static func validateArchiveSHA256(at archive: URL, expected: String) throws {
        let normalizedExpected = expected.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedExpected.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw WhiskyWineInstallerError.invalidArchiveChecksum
        }

        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == normalizedExpected else {
            throw WhiskyWineInstallerError.archiveChecksumMismatch
        }
    }

    private static func isKnownNonArchiveContentType(_ contentType: String?) -> Bool {
        guard let contentType = contentType?.lowercased() else { return false }
        return contentType.hasPrefix("text/")
            || contentType.contains("json")
            || contentType.contains("xml")
            || contentType.contains("html")
    }

    private static func isLibrariesRootEntry(_ entry: String) -> Bool {
        entry == "Libraries" || entry == "Libraries/" || entry.hasPrefix("Libraries/")
    }
}

struct WhiskyWineVersionInfo: Codable {
    var version: SemanticVersion?

    enum CodingKeys: String, CodingKey {
        case version
    }

    init(version: SemanticVersion? = nil) {
        self.version = version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let versionString = try? container.decode(String.self, forKey: .version),
           let semanticVersion = SemanticVersion(versionString) {
            version = semanticVersion
            return
        }

        version = try container.decodeIfPresent(SemanticVersion.self, forKey: .version)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(version, forKey: .version)
    }
}

public struct RuntimeDiscovery: Sendable, Equatable {
    public enum State: String, Sendable, Equatable {
        case missing = "missing"
        case installedUnverified = "installed_unverified"
        case gatekeeperBlocked = "gatekeeper_blocked"
        case ready = "ready"
        case corruptOrIncomplete = "corrupt_or_incomplete"
        case unsupported = "unsupported"
        case verificationFailed = "verification_failed"
    }

    public let state: State
    public let readiness: RuntimeReadiness?
    public let wineVersion: String?
    public let errorDescription: String?

    public init(
        state: State,
        readiness: RuntimeReadiness? = nil,
        wineVersion: String? = nil,
        errorDescription: String? = nil
    ) {
        self.state = state
        self.readiness = readiness
        self.wineVersion = wineVersion
        self.errorDescription = errorDescription
    }

    public var requiresDownload: Bool {
        switch state {
        case .missing, .corruptOrIncomplete, .unsupported:
            return true
        case .installedUnverified, .gatekeeperBlocked, .ready, .verificationFailed:
            return false
        }
    }
}

/// Result of validating an installed BourbonWine runtime. This is intentionally
/// filesystem-and-process based so a leftover directory or plist cannot suppress
/// setup after an interrupted migration or extraction.
public struct RuntimeReadiness: Sendable, Equatable {
    public let failures: [String]
    public let wineVersion: String?

    public var isReady: Bool { failures.isEmpty }
    public var hasRequiredFiles: Bool {
        !failures.contains(where: { $0.hasPrefix("missing:") || $0.hasPrefix("not_executable:") })
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func validate(
        applicationFolder: URL,
        librariesFolder: URL? = nil,
        expectedRuntimeVersion: String? = nil,
        requireVersionMarker: Bool = true,
        runWineVersion: Bool = true,
        fileManager: FileManager = .default
    ) -> RuntimeReadiness {
        let libraries = librariesFolder ?? applicationFolder.appending(path: "Libraries")
        let wineRoot = libraries.appending(path: "Wine")
        let wine = wineRoot.appending(path: "bin/wine")
        let wineserver = wineRoot.appending(path: "bin/wineserver")
        let ntdll = wineRoot.appending(path: "lib/wine/x86_64-unix/ntdll.so")
        let vulkan = wineRoot.appending(path: "lib/libvulkan.1.dylib")
        var failures: [String] = []

        for item in [wine, wineserver, ntdll, vulkan] where !fileManager.fileExists(atPath: item.path) {
            failures.append("missing:\(item.path)")
        }
        for executable in [wine, wineserver]
        where fileManager.fileExists(atPath: executable.path)
            && !fileManager.isExecutableFile(atPath: executable.path) {
            failures.append("not_executable:\(executable.path)")
        }

        let manifestURL = libraries.appending(path: "BourbonWineRuntime.json")
        var manifest: InstalledRuntimeManifest?
        do {
            manifest = try JSONDecoder().decode(InstalledRuntimeManifest.self, from: Data(contentsOf: manifestURL))
            if SemanticVersion(manifest?.runtimeVersion ?? "") == nil {
                failures.append("invalid_manifest_version")
            }
        } catch {
            failures.append("missing_or_invalid_manifest")
        }

        if let expectedRuntimeVersion, manifest?.runtimeVersion != expectedRuntimeVersion {
            failures.append("runtime_version_mismatch")
        }

        if requireVersionMarker {
            let markerURL = libraries.appending(path: "BourbonWineVersion.plist")
            do {
                let marker = try PropertyListDecoder().decode(
                    WhiskyWineVersionInfo.self,
                    from: Data(contentsOf: markerURL)
                )
                if marker.version.map(String.init(describing:)) != manifest?.runtimeVersion {
                    failures.append("installed_version_marker_mismatch")
                }
            } catch {
                failures.append("missing_or_invalid_installed_version_marker")
            }
        }

        guard failures.isEmpty else { return RuntimeReadiness(failures: failures, wineVersion: nil) }
        guard runWineVersion else { return RuntimeReadiness(failures: [], wineVersion: nil) }
        do {
            let version = try wineVersion(at: wine, wineRoot: wineRoot)
            guard WineSemanticVersion.versionToken(from: version) != nil else {
                return RuntimeReadiness(failures: ["invalid_wine_version_output"], wineVersion: nil)
            }
            if let expectedWineVersion = manifest?.wineVersion,
               !version.lowercased().contains(expectedWineVersion.lowercased()) {
                return RuntimeReadiness(failures: ["wine_version_mismatch"], wineVersion: version)
            }
            return RuntimeReadiness(failures: [], wineVersion: version)
        } catch WhiskyWineInstallerError.wineVersionTimedOut {
            return RuntimeReadiness(failures: ["wine_version_timed_out"], wineVersion: nil)
        } catch {
            return RuntimeReadiness(failures: ["wine_version_failed"], wineVersion: nil)
        }
    }

    private static func wineVersion(at executable: URL, wineRoot: URL) throws -> String {
        let process = Process()
        let output = Pipe()
        let processExit = DispatchSemaphore(value: 0)
        WhiskyWineInstaller.recordRuntimeEvent("runtime.wine_version.started")
        WhiskyWineInstaller.recordRuntimeEvent(
            "runtime.gatekeeper_check",
            detail: "executable_present=\(FileManager.default.fileExists(atPath: executable.path))"
        )
        process.executableURL = executable
        process.arguments = ["--version"]
        process.currentDirectoryURL = executable.deletingLastPathComponent()
        process.environment = [
            "PATH": wineRoot.appending(path: "bin").path + ":/usr/bin:/bin:/usr/sbin:/sbin",
            "DYLD_LIBRARY_PATH": wineRoot.appending(path: "lib").path,
            "DYLD_FALLBACK_LIBRARY_PATH": wineRoot.appending(path: "lib").path
        ]
        process.standardOutput = output
        process.standardError = output
        process.terminationHandler = { _ in processExit.signal() }
        do {
            try process.run()
        } catch {
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.wine_version.failed",
                detail: "stage=launch error=\(WineDiagnosticSanitizer.singleLine(error.localizedDescription))"
            )
            throw error
        }
        guard processExit.wait(timeout: .now() + 30) == .success else {
            process.terminate()
            _ = processExit.wait(timeout: .now() + 2)
            WhiskyWineInstaller.recordRuntimeEvent("runtime.wine_version.failed", detail: "stage=timeout_seconds_30")
            throw WhiskyWineInstallerError.wineVersionTimedOut
        }
        let data = try output.fileHandleForReading.readToEnd() ?? Data()
        guard process.terminationStatus == 0 else {
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.wine_version.failed",
                detail: "stage=terminated exit_status=\(process.terminationStatus)"
            )
            throw WhiskyWineInstallerError.wineVersionFailed
        }
        WhiskyWineInstaller.recordRuntimeEvent("runtime.wine_version.completed")
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private struct InstalledRuntimeManifest: Codable {
    let runtimeVersion: String
    let wineVersion: String
}

enum WhiskyWineInstallerError: LocalizedError {
    case missingBundledDiagnosticRuntime
    case invalidRuntimeVersion(String)
    case invalidArchiveChecksum
    case archiveChecksumMismatch
    case missingHTTPResponse(URL)
    case badHTTPStatus(URL, Int)
    case invalidContentType(URL, String)
    case invalidArchive(URL?, URL, String?)
    case invalidArchiveLayout(URL?, URL)
    case runtimeNotReady(RuntimeReadiness)
    case wineVersionFailed
    case wineVersionTimedOut

    var errorDescription: String? {
        switch self {
        case .missingBundledDiagnosticRuntime:
            return "This diagnostic Bourbon build does not include its required BourbonWine runtime archive."
        case .invalidRuntimeVersion:
            return "BourbonWine update metadata contains an invalid runtime version."
        case .invalidArchiveChecksum:
            return "BourbonWine update metadata contains an invalid archive checksum."
        case .archiveChecksumMismatch:
            return "The downloaded BourbonWine archive did not match its expected checksum."
        case .missingHTTPResponse(let url):
            return "BourbonWine download did not return an HTTP response: \(url.absoluteString)"
        case .badHTTPStatus(let url, let statusCode):
            return "BourbonWine download failed with HTTP \(statusCode): \(url.absoluteString)"
        case .invalidContentType(let url, let contentType):
            return "BourbonWine download returned \(contentType), not a tar.gz archive: \(url.absoluteString)"
        case .invalidArchive(let sourceURL, let savedURL, let reason):
            let source = sourceURL?.absoluteString ?? "local file"
            var message = "BourbonWine download is not a valid tar.gz archive: \(source) saved at \(savedURL.path)"
            if let reason, !reason.isEmpty {
                message += ". \(reason)"
            }
            return message
        case .invalidArchiveLayout(let sourceURL, let savedURL):
            let source = sourceURL?.absoluteString ?? "local file"
            return "BourbonWine archive does not contain a Libraries folder: \(source) saved at \(savedURL.path)"
        case .runtimeNotReady(let readiness):
            return "BourbonWine runtime validation failed: \(readiness.failures.joined(separator: ", "))"
        case .wineVersionFailed:
            return "BourbonWine wine --version failed during runtime validation."
        case .wineVersionTimedOut:
            return "BourbonWine wine --version did not finish within 30 seconds. "
                + "macOS may still be blocking the executable; use Privacy & Security to allow it, then retry."
        }
    }
}

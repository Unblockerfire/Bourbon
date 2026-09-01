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
#if canImport(Darwin)
import Darwin
#endif

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
        recordRuntimeEvent("runtime.archive.selected", detail: "source=bundled_diagnostic_runtime")
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
            let installTask = Task.detached(priority: .userInitiated) {
                try installBundledDiagnosticRuntime(in: bundle, into: destinationApplicationFolder)
            }
            return try await withTaskCancellationHandler {
                try await installTask.value
            } onCancel: {
                installTask.cancel()
            }
        }

        let runtimeInfo = try await latestRuntimeInfo()
        guard SemanticVersion(runtimeInfo.version) != nil else {
            throw WhiskyWineInstallerError.invalidRuntimeVersion(runtimeInfo.version)
        }

        recordUpdateEvent("runtime.update.download.started", detail: "source=runtime_manifest")
        recordRuntimeEvent("runtime.archive.selected", detail: "source=runtime_manifest")
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
        let installTask = Task.detached(priority: .userInitiated) {
            try install(from: archive, runtimeVersion: runtimeInfo.version, into: destinationApplicationFolder)
        }
        try await withTaskCancellationHandler {
            try await installTask.value
        } onCancel: {
            installTask.cancel()
        }
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

    public static func isWhiskyWineInstalled() -> Bool {
        runtimeReadiness(in: applicationFolder).isReady
    }

    public static func runtimeBinariesInstalled() -> Bool {
        runtimeReadiness(in: applicationFolder).hasRequiredFiles
    }

    /// The only authoritative statement that a runtime is ready.  A version marker is
    /// deliberately not sufficient: it is written last and is checked against the
    /// manifest shipped inside the runtime itself.
    public static func runtimeReadiness(
        in applicationFolder: URL,
        phase: String = "readiness"
    ) -> RuntimeReadiness {
        RuntimeReadiness.validate(applicationFolder: applicationFolder, phase: phase)
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
        var shouldRemoveStaging = true
        defer {
            if let stagingRoot, shouldRemoveStaging {
                try? fileManager.removeItem(at: stagingRoot)
            }
        }

        do {
            try validateArchive(at: from, sourceURL: nil)
            recordRuntimeEvent(
                "runtime.install.destination",
                detail: "path=\(WineDiagnosticSanitizer.redact(destinationApplicationFolder.path))"
            )

            if !fileManager.fileExists(atPath: destinationApplicationFolder.path) {
                try fileManager.createDirectory(at: destinationApplicationFolder, withIntermediateDirectories: true)
            }

            let staging = destinationApplicationFolder.appending(path: ".BourbonWineInstall-Staged")
            stagingRoot = staging
            let reusableStaging = fileManager.fileExists(atPath: staging.path(percentEncoded: false))
                && RuntimeReadiness.validate(
                    applicationFolder: staging,
                    expectedRuntimeVersion: runtimeVersion,
                    requireVersionMarker: false,
                    runWineVersion: false,
                    phase: "staged_reuse_check"
                ).isReady

            recordUpdateEvent("runtime.update.extraction.started")
            if reusableStaging {
                shouldRemoveStaging = false
                recordRuntimeEvent("runtime.extract.started", detail: "mode=reuse_preserved_staging")
                recordRuntimeEvent("runtime.extract.completed", detail: "mode=reuse_preserved_staging")
            } else {
                if fileManager.fileExists(atPath: staging.path(percentEncoded: false)) {
                    try fileManager.removeItem(at: staging)
                }
                try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
                recordRuntimeEvent("runtime.extract.started", detail: "mode=fresh")
                do {
                    try Tar.untar(tarBall: from, toURL: staging)
                } catch {
                    let safeError = WineDiagnosticSanitizer.singleLine(error.localizedDescription)
                    recordRuntimeEvent("runtime.extract.failed", detail: "error=\(safeError)")
                    throw error
                }
                try Task.checkCancellation()
                shouldRemoveStaging = false
                recordRuntimeEvent("runtime.extract.completed", detail: "mode=fresh")
            }
            recordUpdateEvent("runtime.update.extraction.completed")

            let stagedReadiness = RuntimeReadiness.validate(
                applicationFolder: staging,
                expectedRuntimeVersion: runtimeVersion,
                requireVersionMarker: false,
                phase: "staged"
            )
            try Task.checkCancellation()
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

            if fileManager.fileExists(atPath: destinationLibraryFolder.path(percentEncoded: false)) {
                let backup = destinationApplicationFolder.appending(path: ".BourbonWineBackup-\(UUID().uuidString)")
                backupLibraryFolder = backup
                try fileManager.moveItem(at: destinationLibraryFolder, to: backup)
            }

            do {
                recordUpdateEvent("runtime.update.install.started")
                recordRuntimeEvent("runtime.install.started", detail: "phase=transactional_swap")
                try fileManager.moveItem(at: staging.appending(path: "Libraries"), to: destinationLibraryFolder)
                shouldRemoveStaging = true
                try writeInstalledVersionMarkerIfNeeded(runtimeVersion: runtimeVersion, in: destinationLibraryFolder)
                recordUpdateEvent("runtime.update.preflight.started")
                let installedReadiness = RuntimeReadiness.validate(
                    applicationFolder: destinationApplicationFolder,
                    expectedRuntimeVersion: runtimeVersion,
                    phase: "installed"
                )
                try Task.checkCancellation()
                guard installedReadiness.isReady else {
                    throw WhiskyWineInstallerError.runtimeNotReady(installedReadiness)
                }
                recordUpdateEvent("runtime.update.preflight.completed")
                recordUpdateEvent("runtime.update.install.completed")
                recordRuntimeEvent("runtime.install.completed", detail: "phase=transactional_swap")
            } catch {
                if fileManager.fileExists(atPath: destinationLibraryFolder.path(percentEncoded: false)) {
                    let preservedLibraries = staging.appending(path: "Libraries")
                    var preservedFailedRuntime = false
                    if !fileManager.fileExists(atPath: preservedLibraries.path(percentEncoded: false)) {
                        do {
                            try fileManager.moveItem(at: destinationLibraryFolder, to: preservedLibraries)
                            preservedFailedRuntime = true
                        } catch {
                            preservedFailedRuntime = false
                        }
                    }
                    if preservedFailedRuntime {
                        shouldRemoveStaging = false
                    } else {
                        try? fileManager.removeItem(at: destinationLibraryFolder)
                    }
                }
                if let backupLibraryFolder,
                   fileManager.fileExists(atPath: backupLibraryFolder.path(percentEncoded: false)) {
                    try? fileManager.moveItem(at: backupLibraryFolder, to: destinationLibraryFolder)
                }
                throw error
            }

            if let backupLibraryFolder {
                try? fileManager.removeItem(at: backupLibraryFolder)
            }
            try? fileManager.removeItem(at: from)
        } catch {
            let safeError = WineDiagnosticSanitizer.singleLine(error.localizedDescription)
            if error is CancellationError {
                recordRuntimeEvent("runtime.install.cancelled", detail: "error=cancelled")
            } else {
                recordRuntimeEvent("runtime.install.failed", detail: "error=\(safeError)")
            }
            if !shouldRemoveStaging {
                recordRuntimeEvent(
                    "runtime.install.staging_preserved",
                    detail: "reason=preflight_retry"
                )
            }
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

// swiftlint:disable:next type_body_length
/// Result of validating an installed BourbonWine runtime. This is intentionally
/// filesystem-and-process based so a leftover directory or plist cannot suppress
/// setup after an interrupted migration or extraction.
public struct RuntimeReadiness: Sendable, Equatable {
    static let wineVersionTimeout: TimeInterval = 45

    public let failures: [String]
    public let wineVersion: String?

    public var isReady: Bool { failures.isEmpty }
    public var hasRequiredFiles: Bool {
        !failures.contains(where: { $0.hasPrefix("missing:") || $0.hasPrefix("not_executable:") })
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func validate(
        applicationFolder: URL,
        expectedRuntimeVersion: String? = nil,
        requireVersionMarker: Bool = true,
        fileManager: FileManager = .default,
        runWineVersion: Bool = true,
        wineVersionTimeout: TimeInterval = RuntimeReadiness.wineVersionTimeout,
        phase: String = "readiness"
    ) -> RuntimeReadiness {
        WhiskyWineInstaller.recordRuntimeEvent(
            "runtime.preflight.started",
            detail: "phase=\(phase)"
        )
        let libraries = applicationFolder.appending(path: "Libraries")
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

        guard failures.isEmpty else {
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.readiness.completed",
                detail: "phase=\(phase) ready=false check=filesystem"
            )
            return RuntimeReadiness(failures: failures, wineVersion: nil)
        }
        guard runWineVersion else {
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.readiness.completed",
                detail: "phase=\(phase) ready=true check=filesystem_only"
            )
            return RuntimeReadiness(failures: [], wineVersion: nil)
        }
        do {
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.gatekeeper_check",
                detail: "phase=\(phase) quarantine=\(quarantineState(for: wine)) " +
                    "assessment=\(gatekeeperAssessment(for: wine))"
            )
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.wine_version.started",
                detail: "phase=\(phase) timeout_seconds=\(Int(wineVersionTimeout))"
            )
            let version = try wineVersion(
                at: wine,
                wineRoot: wineRoot,
                timeout: wineVersionTimeout
            )
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.wine_version.completed",
                detail: "phase=\(phase) outcome=success"
            )
            guard WineSemanticVersion.versionToken(from: version) != nil else {
                WhiskyWineInstaller.recordRuntimeEvent(
                    "runtime.readiness.completed",
                    detail: "phase=\(phase) ready=false check=wine_version_output"
                )
                return RuntimeReadiness(failures: ["invalid_wine_version_output"], wineVersion: nil)
            }
            if let expectedWineVersion = manifest?.wineVersion,
               !version.lowercased().contains(expectedWineVersion.lowercased()) {
                WhiskyWineInstaller.recordRuntimeEvent(
                    "runtime.readiness.completed",
                    detail: "phase=\(phase) ready=false check=wine_version_match"
                )
                return RuntimeReadiness(failures: ["wine_version_mismatch"], wineVersion: version)
            }
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.readiness.completed",
                detail: "phase=\(phase) ready=true"
            )
            return RuntimeReadiness(failures: [], wineVersion: version)
        } catch let error as RuntimeWineVersionError {
            let safeError = WineDiagnosticSanitizer.singleLine(error.localizedDescription)
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.wine_version.completed",
                detail: "phase=\(phase) outcome=failure code=\(error.diagnosticCode) error=\(safeError)"
            )
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.readiness.completed",
                detail: "phase=\(phase) ready=false check=\(error.diagnosticCode)"
            )
            return RuntimeReadiness(failures: [error.failureCode(phase: phase)], wineVersion: nil)
        } catch is CancellationError {
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.wine_version.completed",
                detail: "phase=\(phase) outcome=cancelled code=wine_version_cancelled"
            )
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.readiness.completed",
                detail: "phase=\(phase) ready=false check=wine_version_cancelled"
            )
            return RuntimeReadiness(failures: ["wine_version_cancelled:\(phase)"], wineVersion: nil)
        } catch {
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.wine_version.completed",
                detail: "phase=\(phase) outcome=failure code=wine_version_failed"
            )
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.readiness.completed",
                detail: "phase=\(phase) ready=false check=wine_version_failed"
            )
            return RuntimeReadiness(failures: ["wine_version_failed"], wineVersion: nil)
        }
    }

    static func wineVersion(
        at executable: URL,
        wineRoot: URL,
        timeout: TimeInterval
    ) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--version"]
        process.currentDirectoryURL = executable.deletingLastPathComponent()
        process.environment = [
            "PATH": wineRoot.appending(path: "bin").path + ":/usr/bin:/bin:/usr/sbin:/sbin",
            "DYLD_LIBRARY_PATH": wineRoot.appending(path: "lib").path,
            "DYLD_FALLBACK_LIBRARY_PATH": wineRoot.appending(path: "lib").path
        ]
        let result = try runBounded(process: process, timeout: timeout)
        guard result.status == 0 else {
            throw RuntimeWineVersionError.nonzeroExit(
                status: result.status,
                reason: result.reason,
                output: WineDiagnosticSanitizer.excerpt(from: result.output)
            )
        }
        return result.output
    }

    private static func quarantineState(for executable: URL) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-p", "com.apple.quarantine", executable.path(percentEncoded: false)]
        do {
            let result = try runBounded(process: process, timeout: 3)
            if result.status == 0 && !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "present"
            }
            return "absent"
        } catch let error as RuntimeWineVersionError {
            return "unknown_\(error.diagnosticCode)"
        } catch {
            return "unknown"
        }
    }

    private static func gatekeeperAssessment(for executable: URL) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/spctl")
        process.arguments = ["--assess", "--type", "execute", executable.path(percentEncoded: false)]
        do {
            let result = try runBounded(process: process, timeout: 5)
            return result.status == 0 ? "accepted" : "rejected"
        } catch let error as RuntimeWineVersionError {
            return "unknown_\(error.diagnosticCode)"
        } catch {
            return "unknown"
        }
    }

    static func runBounded(process: Process, timeout: TimeInterval) throws -> RuntimeProcessResult {
        let fileManager = FileManager.default
        let captureURL = fileManager.temporaryDirectory
            .appending(path: "BourbonRuntimeProcess-\(UUID().uuidString).log")
        guard fileManager.createFile(atPath: captureURL.path, contents: nil) else {
            throw RuntimeWineVersionError.captureFailed
        }
        defer { try? fileManager.removeItem(at: captureURL) }

        let writer = try FileHandle(forWritingTo: captureURL)
        process.standardOutput = writer
        process.standardError = writer
        do {
            try process.run()
        } catch {
            try? writer.close()
            throw RuntimeWineVersionError.launchFailed(
                WineDiagnosticSanitizer.singleLine(error.localizedDescription)
            )
        }
        try? writer.close()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            if withUnsafeCurrentTask(body: { $0?.isCancelled ?? false }) {
                stop(process)
                throw CancellationError()
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            stop(process)
            throw RuntimeWineVersionError.timeout(seconds: timeout)
        }

        let data = (try? Data(contentsOf: captureURL)) ?? Data()
        let output = String(data: data, encoding: .utf8) ?? ""
        return RuntimeProcessResult(
            status: process.terminationStatus,
            reason: process.terminationReason.runtimeDiagnosticDescription,
            output: output
        )
    }

    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let graceDeadline = Date().addingTimeInterval(1)
        while process.isRunning && Date() < graceDeadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        #if canImport(Darwin)
        if process.isRunning {
            _ = Darwin.kill(process.processIdentifier, SIGKILL)
            let killDeadline = Date().addingTimeInterval(1)
            while process.isRunning && Date() < killDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        #endif
    }
}

struct RuntimeProcessResult: Sendable, Equatable {
    let status: Int32
    let reason: String
    let output: String
}

enum RuntimeWineVersionError: LocalizedError, Equatable {
    case captureFailed
    case launchFailed(String)
    case timeout(seconds: TimeInterval)
    case nonzeroExit(status: Int32, reason: String, output: String)

    var diagnosticCode: String {
        switch self {
        case .captureFailed: return "wine_version_capture_failed"
        case .launchFailed: return "wine_version_launch_failed"
        case .timeout: return "wine_version_timeout"
        case .nonzeroExit: return "wine_version_nonzero_exit"
        }
    }

    func failureCode(phase: String) -> String {
        switch self {
        case .nonzeroExit(let status, _, _):
            return "wine_version_nonzero_exit_status_\(status):\(phase)"
        default:
            return "\(diagnosticCode):\(phase)"
        }
    }

    var errorDescription: String? {
        switch self {
        case .captureFailed:
            return "Bourbon could not create a safe diagnostic capture for wine --version."
        case .launchFailed(let detail):
            return "macOS rejected the BourbonWine preflight launch: \(detail)"
        case .timeout(let seconds):
            return "BourbonWine wine --version did not finish within \(Int(seconds)) seconds. " +
                "macOS may still be waiting for an Open confirmation after Allow Anyway."
        case .nonzeroExit(let status, let reason, let output):
            return "BourbonWine wine --version exited with status \(status) (\(reason)): \(output)"
        }
    }
}

private extension Process.TerminationReason {
    var runtimeDiagnosticDescription: String {
        switch self {
        case .exit: return "exit"
        case .uncaughtSignal: return "uncaught_signal"
        @unknown default: return "unknown"
        }
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
            if let timeout = readiness.failures.first(where: { $0.hasPrefix("wine_version_timeout:") }) {
                let phase = timeout.split(separator: ":").last.map(String.init) ?? "unknown"
                return "BourbonWine wine --version timed out after " +
                    "\(Int(RuntimeReadiness.wineVersionTimeout)) seconds during the \(phase) preflight. " +
                    "The existing runtime was restored. macOS may still require an Open confirmation."
            }
            if let launch = readiness.failures.first(where: { $0.hasPrefix("wine_version_launch_failed:") }) {
                let phase = launch.split(separator: ":").last.map(String.init) ?? "unknown"
                return "macOS rejected BourbonWine during the \(phase) preflight. " +
                    "The existing runtime was restored. Check Privacy & Security, then retry."
            }
            if let nonzero = readiness.failures.first(where: { $0.hasPrefix("wine_version_nonzero_exit_status_") }) {
                let components = nonzero.split(separator: ":", maxSplits: 1).map(String.init)
                let status = components[0].replacingOccurrences(
                    of: "wine_version_nonzero_exit_status_",
                    with: ""
                )
                let phase = components.count > 1 ? components[1] : "unknown"
                return "BourbonWine wine --version exited with status \(status) during the \(phase) preflight. " +
                    "The existing runtime was restored."
            }
            return "BourbonWine runtime validation failed: \(readiness.failures.joined(separator: ", "))"
        case .wineVersionFailed:
            return "BourbonWine wine --version failed during runtime validation."
        }
    }
}

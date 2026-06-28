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

import Foundation
import SemanticVersion
import os.log

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
    public static let defaultRuntimeAPIBaseURLString = "https://bourbonruntimeapi.fly.dev"

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

    public static func latestRuntimeInfo() async throws -> BourbonRuntimeInfo {
        let request = URLRequest(url: runtimeAPIBaseURL.appending(path: "runtime/latest"))
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        try validateVersionResponse(response, sourceURL: request.url ?? runtimeAPIBaseURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(BourbonRuntimeInfo.self, from: data)
    }

    /// The Whisky application folder
    public static let applicationFolder = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appending(path: Bundle.whiskyBundleIdentifier)

    /// The folder of all the libfrary files
    public static let libraryFolder = applicationFolder.appending(path: "Libraries")

    /// URL to the installed `wine` `bin` directory
    public static let binFolder: URL = libraryFolder.appending(path: "Wine").appending(path: "bin")

    public static func isWhiskyWineInstalled() -> Bool {
        if whiskyWineVersion() != nil {
            return true
        }

        guard runtimeBinariesInstalled() else {
            return false
        }

        do {
            try writeInstalledVersionMarkerIfNeeded()
        } catch {
            Logger.wineKit.warning("BourbonWine binaries are present, but marker creation failed: \(error)")
        }

        return true
    }

    public static func runtimeBinariesInstalled() -> Bool {
        let wine = binFolder.appending(path: "wine")
        let wineserver = binFolder.appending(path: "wineserver")
        return FileManager.default.fileExists(atPath: wine.path(percentEncoded: false))
            && FileManager.default.fileExists(atPath: wineserver.path(percentEncoded: false))
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

    public static func install(from: URL) throws {
        do {
            try validateArchive(at: from, sourceURL: nil)

            if !FileManager.default.fileExists(atPath: applicationFolder.path) {
                try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
            } else {
                // Recreate it
                try FileManager.default.removeItem(at: applicationFolder)
                try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
            }

            try Tar.untar(tarBall: from, toURL: applicationFolder)
            try writeInstalledVersionMarkerIfNeeded()
            try FileManager.default.removeItem(at: from)
        } catch {
            Logger.wineKit.error("Failed to install WhiskyWine from `\(from.path)`: \(error)")
            throw error
        }
    }

    public static func persistDownloadedArchive(
        at temporaryURL: URL,
        response: URLResponse?,
        sourceURL: URL
    ) throws -> URL {
        Logger.wineKit.info(
            "Received WhiskyWine download from `\(sourceURL.absoluteString)` at `\(temporaryURL.path)`"
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
            "Downloaded WhiskyWine from `\(sourceURL.absoluteString)` to `\(savedURL.path(percentEncoded: false))`"
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
            "Using local WhiskyWine archive `\(url.path(percentEncoded: false))` copied to `\(savedURL.path)`"
        )
        return savedURL
    }

    public static func uninstall() {
        do {
            try FileManager.default.removeItem(at: libraryFolder)
        } catch {
            print("Failed to uninstall WhiskyWine: \(error)")
        }
    }

    public static func shouldUpdateWhiskyWine() async -> (Bool, SemanticVersion) {
        let localVersion = whiskyWineVersion()
        let remoteVersion = await remotewhiskyWineVersion()

        if let localVersion = localVersion, let remoteVersion = remoteVersion {
            if localVersion < remoteVersion {
                return (true, remoteVersion)
            }
        }

        return (false, SemanticVersion(0, 0, 0))
    }

    public static func whiskyWineVersion() -> SemanticVersion? {
        guard let versionPlist = installedVersionPlistURL() else {
            return nil
        }

        do {
            let decoder = PropertyListDecoder()
            let data = try Data(contentsOf: versionPlist)
            let info = try decoder.decode(WhiskyWineVersionInfo.self, from: data)
            return info.version
        } catch {
            Logger.wineKit.error("Failed to read WhiskyWine version plist `\(versionPlist.path)`: \(error)")
            return nil
        }
    }

    private static func installedVersionPlistURL() -> URL? {
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

    private static func writeInstalledVersionMarkerIfNeeded() throws {
        let marker = libraryFolder
            .appending(path: "BourbonWineVersion")
            .appendingPathExtension("plist")

        if FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)) {
            return
        }

        if !FileManager.default.fileExists(atPath: libraryFolder.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
        }

        let data = try PropertyListEncoder().encode(WhiskyWineVersionInfo())
        try data.write(to: marker, options: .atomic)
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
            Logger.wineKit.warning("Failed to load remote WhiskyWine version from `\(versionURL)`: \(error)")
            return nil
        }
    }

    private static func configuredURL(forKey key: String, defaultValue: String) -> URL {
        let string = UserDefaults.standard.string(forKey: key) ?? defaultValue
        if let url = URL(string: string) {
            return url
        }

        Logger.wineKit.error("Invalid WhiskyWine URL configured for `\(key)`: \(string)")
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
    var version: SemanticVersion = SemanticVersion(1, 0, 0)

    enum CodingKeys: String, CodingKey {
        case version
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let versionString = try? container.decode(String.self, forKey: .version),
           let semanticVersion = SemanticVersion(versionString) {
            version = semanticVersion
            return
        }

        version = try container.decode(SemanticVersion.self, forKey: .version)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
    }
}

enum WhiskyWineInstallerError: LocalizedError {
    case missingHTTPResponse(URL)
    case badHTTPStatus(URL, Int)
    case invalidContentType(URL, String)
    case invalidArchive(URL?, URL, String?)
    case invalidArchiveLayout(URL?, URL)

    var errorDescription: String? {
        switch self {
        case .missingHTTPResponse(let url):
            return "WhiskyWine download did not return an HTTP response: \(url.absoluteString)"
        case .badHTTPStatus(let url, let statusCode):
            return "WhiskyWine download failed with HTTP \(statusCode): \(url.absoluteString)"
        case .invalidContentType(let url, let contentType):
            return "WhiskyWine download returned \(contentType), not a tar.gz archive: \(url.absoluteString)"
        case .invalidArchive(let sourceURL, let savedURL, let reason):
            let source = sourceURL?.absoluteString ?? "local file"
            var message = "WhiskyWine download is not a valid tar.gz archive: \(source) saved at \(savedURL.path)"
            if let reason, !reason.isEmpty {
                message += ". \(reason)"
            }
            return message
        case .invalidArchiveLayout(let sourceURL, let savedURL):
            let source = sourceURL?.absoluteString ?? "local file"
            return "WhiskyWine archive does not contain a Libraries folder: \(source) saved at \(savedURL.path)"
        }
    }
}

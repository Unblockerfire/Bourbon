//
//  DiagnosticAppInstaller.swift
//  WhiskyKit
//

import Foundation

public struct DiagnosticBuildIdentity: Codable, Equatable, Sendable {
    public let gitCommit: String?
    public let marketingVersion: String?
    public let buildNumber: String?
    public let buildDateUTC: String?

    public init(
        gitCommit: String?,
        marketingVersion: String?,
        buildNumber: String?,
        buildDateUTC: String?
    ) {
        self.gitCommit = gitCommit
        self.marketingVersion = marketingVersion
        self.buildNumber = buildNumber
        self.buildDateUTC = buildDateUTC
    }

    public var commitDisplay: String {
        guard let gitCommit, !gitCommit.isEmpty else { return "Unavailable" }
        return String(gitCommit.prefix(12))
    }

    public var versionDisplay: String {
        let version = marketingVersion ?? "Unknown"
        let build = buildNumber ?? "Unknown"
        return "\(version) (\(build))"
    }

    public static func load(from appURL: URL, fileManager: FileManager = .default) -> Self {
        let buildInfoURL = appURL
            .appending(path: "Contents/Resources/BuildInfo.json")
        if let data = fileManager.contents(atPath: buildInfoURL.path),
           let identity = try? JSONDecoder().decode(Self.self, from: data) {
            return identity
        }

        let infoURL = appURL.appending(path: "Contents/Info.plist")
        let info = NSDictionary(contentsOf: infoURL) as? [String: Any]
        return Self(
            gitCommit: nil,
            marketingVersion: info?["CFBundleShortVersionString"] as? String,
            buildNumber: info?["CFBundleVersion"] as? String,
            buildDateUTC: nil
        )
    }
}

public struct DiagnosticInstalledCopy: Equatable, Sendable {
    public let url: URL
    public let identity: DiagnosticBuildIdentity

    public init(url: URL, identity: DiagnosticBuildIdentity) {
        self.url = url
        self.identity = identity
    }
}

public enum DiagnosticAppInstallationPolicy {
    public static let appName = "Bourbon Diagnostic.app"
    public static let displayName = "Bourbon Diagnostic"

    public static var destinationURL: URL {
        destination(in: URL(fileURLWithPath: "/Applications", isDirectory: true))
    }

    public static func destination(in applicationsDirectory: URL) -> URL {
        applicationsDirectory.appending(path: appName, directoryHint: .isDirectory)
    }

    public static func isDiagnosticBuild(displayName: String?) -> Bool {
        displayName == Self.displayName
    }

    public static func requiresInstallation(bundleURL: URL, displayName: String?) -> Bool {
        guard isDiagnosticBuild(displayName: displayName) else { return false }
        return normalized(bundleURL) != normalized(destinationURL)
    }

    public static func isInstalledDestination(_ bundleURL: URL) -> Bool {
        normalized(bundleURL) == normalized(destinationURL)
    }

    public static func inspectExistingCopy(
        in applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
        fileManager: FileManager = .default
    ) -> DiagnosticInstalledCopy? {
        let url = destination(in: applicationsDirectory)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return DiagnosticInstalledCopy(
            url: url,
            identity: DiagnosticBuildIdentity.load(from: url, fileManager: fileManager)
        )
    }

    public static func validateDestination(_ destination: URL, applicationsDirectory: URL) throws {
        let expected = self.destination(in: applicationsDirectory)
        guard normalized(destination) == normalized(expected),
              destination.lastPathComponent == appName,
              destination.lastPathComponent != "Bourbon.app" else {
            throw DiagnosticAppInstallationError.unsafeDestination
        }
    }

    private static func normalized(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

public struct DiagnosticCopyProgress: Equatable, Sendable {
    public let bytesCopied: Int64
    public let totalBytes: Int64
    public let filesCopied: Int
    public let totalFiles: Int

    public init(bytesCopied: Int64, totalBytes: Int64, filesCopied: Int, totalFiles: Int) {
        self.bytesCopied = bytesCopied
        self.totalBytes = totalBytes
        self.filesCopied = filesCopied
        self.totalFiles = totalFiles
    }

    public var fractionCompleted: Double {
        if totalBytes > 0 {
            return min(1, Double(bytesCopied) / Double(totalBytes))
        }
        guard totalFiles > 0 else { return 1 }
        return min(1, Double(filesCopied) / Double(totalFiles))
    }
}

public enum DiagnosticAppInstallationError: LocalizedError, Equatable, Sendable {
    case sourceIsNotAppBundle
    case destinationExists
    case unsafeDestination
    case copiedBundleCouldNotBeVerified

    public var errorDescription: String? {
        switch self {
        case .sourceIsNotAppBundle:
            return "The running Bourbon Diagnostic app bundle could not be read."
        case .destinationExists:
            return "A Bourbon Diagnostic copy already exists in Applications."
        case .unsafeDestination:
            return "Bourbon refused to copy to an unsafe destination."
        case .copiedBundleCouldNotBeVerified:
            return "The copied Bourbon Diagnostic app could not be verified."
        }
    }
}

public final class DiagnosticAppBundleCopier: @unchecked Sendable {
    private let fileManager: FileManager
    private let applicationsDirectory: URL

    public init(
        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.applicationsDirectory = applicationsDirectory
        self.fileManager = fileManager
    }

    public func copy(
        source: URL,
        replaceExisting: Bool,
        progress: @escaping (DiagnosticCopyProgress) -> Void
    ) throws -> URL {
        let destination = DiagnosticAppInstallationPolicy.destination(in: applicationsDirectory)
        try DiagnosticAppInstallationPolicy.validateDestination(
            destination,
            applicationsDirectory: applicationsDirectory
        )
        guard isAppBundle(source) else {
            throw DiagnosticAppInstallationError.sourceIsNotAppBundle
        }
        let hadExistingDestination = fileManager.fileExists(atPath: destination.path)
        if hadExistingDestination, !replaceExisting {
            throw DiagnosticAppInstallationError.destinationExists
        }

        let staging = applicationsDirectory.appending(
            path: ".Bourbon Diagnostic.app.install-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let backup = applicationsDirectory.appending(
            path: ".Bourbon Diagnostic.app.backup-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )

        do {
            let sourceInventory = try inventory(at: source)
            let sourceIdentity = DiagnosticBuildIdentity.load(from: source, fileManager: fileManager)
            try copyItems(source: source, staging: staging, inventory: sourceInventory, progress: progress)
            try verify(appURL: staging, sourceInventory: sourceInventory, sourceIdentity: sourceIdentity)
            try install(staging: staging, destination: destination, backup: backup, replaceExisting: replaceExisting)
            try verify(appURL: destination, sourceInventory: sourceInventory, sourceIdentity: sourceIdentity)
            try? fileManager.removeItem(at: backup)
            return destination
        } catch {
            try? fileManager.removeItem(at: staging)
            if fileManager.fileExists(atPath: backup.path) {
                try? fileManager.removeItem(at: destination)
                try? fileManager.moveItem(at: backup, to: destination)
            } else if !hadExistingDestination {
                try? fileManager.removeItem(at: destination)
            }
            throw error
        }
    }

    private func isAppBundle(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let info = url.appending(path: "Contents/Info.plist")
        guard exists, isDirectory.boolValue,
              let dictionary = NSDictionary(contentsOf: info) as? [String: Any],
              dictionary["CFBundleDisplayName"] as? String == DiagnosticAppInstallationPolicy.displayName,
              let executableName = dictionary["CFBundleExecutable"] as? String else {
            return false
        }
        let executable = url.appending(path: "Contents/MacOS/\(executableName)")
        return fileManager.isExecutableFile(atPath: executable.path)
    }

    private func inventory(at root: URL) throws -> BundleInventory {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey
            ],
            options: []
        ) else {
            throw DiagnosticAppInstallationError.sourceIsNotAppBundle
        }

        var entries: [BundleEntry] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey
            ])
            let relativeComponents = url.standardizedFileURL.pathComponents
                .dropFirst(root.standardizedFileURL.pathComponents.count)
            let relativePath = relativeComponents.joined(separator: "/")
            entries.append(BundleEntry(
                relativePath: relativePath,
                isDirectory: values.isDirectory == true && values.isSymbolicLink != true,
                byteCount: values.isRegularFile == true ? Int64(values.fileSize ?? 0) : 0
            ))
        }
        return BundleInventory(entries: entries)
    }

    private func copyItems(
        source: URL,
        staging: URL,
        inventory: BundleInventory,
        progress: @escaping (DiagnosticCopyProgress) -> Void
    ) throws {
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        var copiedBytes: Int64 = 0
        var copiedFiles = 0
        progress(inventory.progress(bytes: 0, files: 0))

        for entry in inventory.entries {
            let sourceURL = source.appending(path: entry.relativePath)
            let targetURL = staging.appending(path: entry.relativePath)
            if entry.isDirectory {
                try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: false)
            } else {
                try fileManager.copyItem(at: sourceURL, to: targetURL)
                copiedBytes += entry.byteCount
                copiedFiles += 1
                progress(inventory.progress(bytes: copiedBytes, files: copiedFiles))
            }
        }
    }

    private func install(
        staging: URL,
        destination: URL,
        backup: URL,
        replaceExisting: Bool
    ) throws {
        if fileManager.fileExists(atPath: destination.path) {
            guard replaceExisting else { throw DiagnosticAppInstallationError.destinationExists }
            try fileManager.moveItem(at: destination, to: backup)
        }
        do {
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            if fileManager.fileExists(atPath: backup.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }
    }

    private func verify(
        appURL: URL,
        sourceInventory: BundleInventory,
        sourceIdentity: DiagnosticBuildIdentity
    ) throws {
        guard isAppBundle(appURL) else {
            throw DiagnosticAppInstallationError.copiedBundleCouldNotBeVerified
        }
        let copiedInventory = try inventory(at: appURL)
        let copiedIdentity = DiagnosticBuildIdentity.load(from: appURL, fileManager: fileManager)
        guard copiedInventory.fileCount == sourceInventory.fileCount,
              copiedInventory.totalBytes == sourceInventory.totalBytes,
              copiedIdentity == sourceIdentity else {
            throw DiagnosticAppInstallationError.copiedBundleCouldNotBeVerified
        }
    }
}

private struct BundleEntry: Sendable {
    let relativePath: String
    let isDirectory: Bool
    let byteCount: Int64
}

private struct BundleInventory: Sendable {
    let entries: [BundleEntry]

    var totalBytes: Int64 {
        entries.reduce(0) { $0 + $1.byteCount }
    }

    var fileCount: Int {
        entries.filter { !$0.isDirectory }.count
    }

    func progress(bytes: Int64, files: Int) -> DiagnosticCopyProgress {
        DiagnosticCopyProgress(
            bytesCopied: bytes,
            totalBytes: totalBytes,
            filesCopied: files,
            totalFiles: fileCount
        )
    }
}

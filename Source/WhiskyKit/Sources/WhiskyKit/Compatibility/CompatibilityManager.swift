//
//  CompatibilityManager.swift
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
import os.log

public enum CompatibilityProgress: String, Sendable {
    case analyzingInstaller = "Analyzing installer..."
    case preparingApplication = "Preparing application..."
    case launching = "Launching..."
}
public struct CompatibilityLaunchPlan: Sendable {
    public let executableURL: URL
    public let arguments: [String]
    public let workingDirectory: URL?
    public let analysis: InstallerAnalysis
    public let ruleID: String?
    public let appliedProfiles: [String]
}

public struct CompatibilityContext: Sendable {
    public let bottle: Bottle
    public let arguments: [String]
    public let cacheRoot: URL
}

public protocol CompatibilityRule: Sendable {
    var id: String { get }
    func strategy(for analysis: InstallerAnalysis, context: CompatibilityContext) -> CompatibilityStrategy?
}

public protocol CompatibilityStrategy: Sendable {
    var reason: String { get }
    func prepare(
        analysis: InstallerAnalysis,
        context: CompatibilityContext
    ) async throws -> PreparedCompatibilityTarget
}

public struct PreparedCompatibilityTarget: Sendable {
    public let executableURL: URL
    public let workingDirectory: URL?
}

public protocol CompatibilityLaunchProfile: Sendable {
    var id: String { get }
    var displayName: String { get }
    func applies(to analysis: InstallerAnalysis, target: PreparedCompatibilityTarget) -> Bool
    func arguments(for analysis: InstallerAnalysis, existingArguments: [String]) -> [String]
}

public struct CompatibilityManager: Sendable {
    public static let shared = CompatibilityManager()

    private let detectionService: InstallerDetectionService
    private let rules: [CompatibilityRule]
    private let launchProfiles: [CompatibilityLaunchProfile]

    public init(
        detectionService: InstallerDetectionService = InstallerDetectionService(),
        rules: [CompatibilityRule] = CompatibilityRuleRegistry.defaultRules,
        launchProfiles: [CompatibilityLaunchProfile] = CompatibilityRuleRegistry.defaultLaunchProfiles
    ) {
        self.detectionService = detectionService
        self.rules = rules
        self.launchProfiles = launchProfiles
    }

    public func launchPlan(
        for url: URL,
        bottle: Bottle,
        arguments: [String],
        progress: (@Sendable (CompatibilityProgress) -> Void)? = nil
    ) async throws -> CompatibilityLaunchPlan {
        progress?(.analyzingInstaller)
        let analysis = try detectionService.analyze(url: url)
        let context = CompatibilityContext(
            bottle: bottle,
            arguments: arguments,
            cacheRoot: cacheRoot(for: bottle)
        )

        for rule in rules {
            guard let strategy = rule.strategy(for: analysis, context: context) else {
                continue
            }

            do {
                progress?(.preparingApplication)
                let prepared = try await strategy.prepare(analysis: analysis, context: context)
                Logger.wineKit.info(
                    """
                    Applied compatibility rule \(rule.id, privacy: .public):
                    \(strategy.reason, privacy: .public)
                    """
                )
                progress?(.launching)
                return launchPlan(
                    target: prepared,
                    arguments: arguments,
                    analysis: analysis,
                    ruleID: rule.id
                )
            } catch {
                Logger.wineKit.warning(
                    """
                    Compatibility rule \(rule.id, privacy: .public) failed, falling back to normal launch:
                    \(String(describing: error), privacy: .public)
                    """
                )
            }
        }

        progress?(.launching)
        let target = PreparedCompatibilityTarget(
            executableURL: url,
            workingDirectory: url.deletingLastPathComponent()
        )
        return launchPlan(target: target, arguments: arguments, analysis: analysis, ruleID: nil)
    }

    private func launchPlan(
        target: PreparedCompatibilityTarget,
        arguments: [String],
        analysis: InstallerAnalysis,
        ruleID: String?
    ) -> CompatibilityLaunchPlan {
        var finalArguments = arguments
        var appliedProfiles: [String] = []

        for profile in launchProfiles where profile.applies(to: analysis, target: target) {
            appliedProfiles.append(profile.displayName)
            finalArguments = profile.arguments(for: analysis, existingArguments: finalArguments)
        }

        return CompatibilityLaunchPlan(
            executableURL: target.executableURL,
            arguments: finalArguments,
            workingDirectory: target.workingDirectory,
            analysis: analysis,
            ruleID: ruleID,
            appliedProfiles: appliedProfiles
        )
    }

    private func cacheRoot(for bottle: Bottle) -> URL {
        bottle.url
            .appending(path: "WhiskyCompatibilityCache")
    }
}

public enum CompatibilityRuleRegistry {
    /// Register future built-in, local JSON, or remotely supplied rules here.
    /// Launch code only consumes `CompatibilityManager`, so new rules should not require Wine runner changes.
    public static let defaultRules: [CompatibilityRule] = [
        EmbeddedElectronArchiveRule()
    ]

    /// Register reusable argument profiles here. A future JSON/database profile can feed this same interface.
    public static let defaultLaunchProfiles: [CompatibilityLaunchProfile] = [
        ChromiumWebViewLaunchProfile()
    ]
}

struct ChromiumWebViewLaunchProfile: CompatibilityLaunchProfile {
    let id = "chromium-webview-fallback"
    let displayName = "Chromium/Electron/WebView GPU fallback"

    private let webViewTechnologies: Set<InstallerTechnology> = [
        .electron,
        .chromium,
        .cef,
        .squirrel,
        .steamWebView
    ]

    func applies(to analysis: InstallerAnalysis, target: PreparedCompatibilityTarget) -> Bool {
        !analysis.technologies.isDisjoint(with: webViewTechnologies)
    }

    func arguments(for analysis: InstallerAnalysis, existingArguments: [String]) -> [String] {
        var flags = [
            "--disable-gpu",
            "--disable-gpu-compositing",
            "--no-sandbox",
            "--disable-software-rasterizer=false",
            "--in-process-gpu",
            "--disable-features=VizDisplayCompositor,UseSkiaRenderer,CanvasOopRasterization",
            "--use-angle=swiftshader",
            "--use-gl=swiftshader"
        ]

        if analysis.technologies.contains(.cef) || analysis.technologies.contains(.steamWebView) {
            flags.append("-cef-disable-gpu")
        }

        return existingArguments + flags.filter { flag in
            !existingArguments.containsCompatibilityFlag(flag)
        }
    }
}

private extension Array where Element == String {
    func containsCompatibilityFlag(_ flag: String) -> Bool {
        contains { existing in
            existing.compatibilityFlagKey == flag.compatibilityFlagKey
        }
    }
}

private extension String {
    var compatibilityFlagKey: String {
        split(separator: "=", maxSplits: 1).first.map(String.init) ?? self
    }
}

struct EmbeddedElectronArchiveRule: CompatibilityRule {
    let id = "embedded-electron-archive"

    func strategy(for analysis: InstallerAnalysis, context: CompatibilityContext) -> CompatibilityStrategy? {
        let hasEmbeddedArchive = analysis.payloadHints.contains("app-64.7z")
            || analysis.payloadHints.contains("app-32.7z")
        let isInstaller = analysis.technologies.contains(.nsis)
            || analysis.technologies.contains(.squirrel)
            || analysis.isWindowsInstaller

        guard hasEmbeddedArchive, isInstaller, analysis.technologies.contains(.electron) else {
            return nil
        }

        return EmbeddedArchiveLaunchStrategy(
            archiveNames: ["app-64.7z", "app-32.7z"],
            preferredExecutableName: analysis.url.deletingPathExtension().lastPathComponent + ".exe"
        )
    }
}

struct EmbeddedArchiveLaunchStrategy: CompatibilityStrategy {
    let archiveNames: [String]
    let preferredExecutableName: String

    var reason: String {
        "The installer contains an embedded app archive that is safer to launch directly."
    }

    func prepare(
        analysis: InstallerAnalysis,
        context: CompatibilityContext
    ) async throws -> PreparedCompatibilityTarget {
        guard let extractor = SevenZipExtractor.available() else {
            throw SevenZipExtractor.ExtractionError.toolUnavailable
        }

        let cacheDirectory = context.cacheRoot.appending(path: analysis.cacheKey)
        let appDirectory = cacheDirectory.appending(path: "app")
        let marker = cacheDirectory.appending(path: "prepared.marker")

        if FileManager.default.fileExists(atPath: marker.path),
           let executable = findExecutable(in: appDirectory) {
            return PreparedCompatibilityTarget(
                executableURL: executable,
                workingDirectory: executable.deletingLastPathComponent()
            )
        }

        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let archiveListing = try extractor.list(archive: analysis.url)
        guard let archiveName = archiveNames.first(where: { archiveListing.contains($0) }) else {
            throw SevenZipExtractor.ExtractionError.failed("No embedded app archive was found.")
        }

        let payloadDirectory = cacheDirectory.appending(path: "payload")
        try? FileManager.default.removeItem(at: payloadDirectory)
        try? FileManager.default.removeItem(at: appDirectory)

        try extractor.extract(archive: analysis.url, to: payloadDirectory, include: archiveName)
        let embeddedArchive = payloadDirectory.appending(path: archiveName)
        try extractor.extract(archive: embeddedArchive, to: appDirectory)

        guard let executable = findExecutable(in: appDirectory) else {
            throw SevenZipExtractor.ExtractionError.failed("No launchable Windows application was found.")
        }

        try "prepared".write(to: marker, atomically: true, encoding: .utf8)
        return PreparedCompatibilityTarget(
            executableURL: executable,
            workingDirectory: executable.deletingLastPathComponent()
        )
    }

    private func findExecutable(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let executables = enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "exe" }
            .filter { url in
                guard let peFile = try? PEFile(url: url) else { return false }
                return peFile.architecture == .x64 || peFile.architecture == .x32
            }

        if let preferred = executables.first(where: {
            $0.lastPathComponent.caseInsensitiveCompare(preferredExecutableName) == .orderedSame
        }) {
            return preferred
        }

        return executables.first(where: {
            let name = $0.lastPathComponent.lowercased()
            return name != "update.exe" && name != "squirrel.exe"
        }) ?? executables.first
    }
}

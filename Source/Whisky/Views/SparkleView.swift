//
//  SparkleView.swift
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

import SwiftUI
import Sparkle

/// Bourbon app versions use `MAJOR.MINOR.PATCH`.
///
/// - `MAJOR`: user-visible breaking or large product changes. These must be
///   shown with release notes and require explicit user confirmation.
/// - `MINOR`: normal feature updates and maintenance updates. These remain
///   eligible for automatic updates.
/// - `PATCH`: focused fixes. These remain eligible for automatic
///   updates.
/// - Emergency updates are encoded inside the second number when it has two
///   digits. In `X.13.X`, the `1` is the normal minor version and the `3` is
///   the emergency marker/level. Emergency marker updates remain eligible for
///   automatic updates, but Bourbon identifies them separately for release
///   notes, reporting, and future policy decisions.
///
/// Optional suffixes such as `beta`, `prerelease`, `pre-release`, and `rc`
/// mark a build as pre-release. Pre-release builds are ignored unless the user
/// explicitly opts in from Settings.
struct BourbonUpdateVersion: Equatable {
    let major: Int
    let minor: Int
    let patch: Int
    let suffix: String?

    init?(_ rawVersion: String) {
        let trimmedVersion = rawVersion
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("v")
        let separators = CharacterSet(charactersIn: "-+_ ")
        let suffixStartIndex = trimmedVersion.firstIndex { character in
            String(character).rangeOfCharacter(from: separators) != nil
        } ?? trimmedVersion.endIndex
        let numericPrefix = String(trimmedVersion[..<suffixStartIndex])
        guard !numericPrefix.isEmpty else {
            return nil
        }

        let components = numericPrefix
            .split(separator: ".")
            .map(String.init)
        guard components.count >= 3,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2]) else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch

        let suffix = String(trimmedVersion[suffixStartIndex...])
            .trimmingCharacters(in: separators)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.suffix = suffix.isEmpty ? nil : suffix
    }

    var normalMinor: Int {
        minor >= 10 ? minor / 10 : minor
    }

    var emergencyLevel: Int {
        minor >= 10 ? minor % 10 : 0
    }

    var isPreRelease: Bool {
        guard let suffix else {
            return false
        }

        let normalizedSuffix = suffix.lowercased()
        return normalizedSuffix.contains("beta") ||
        normalizedSuffix.contains("prerelease") ||
        normalizedSuffix.contains("pre-release") ||
        normalizedSuffix.contains("rc")
    }
}

enum BourbonReleaseKind: String {
    case major
    case minor
    case emergency
    case patch
    case unknown
}

struct BourbonReleaseMetadata {
    let currentVersion: String
    let newVersion: String
    let kind: BourbonReleaseKind
    let isPreRelease: Bool
}

enum BourbonUpdatePolicy {
    static let preReleaseUpdatesEnabledKey = "bourbonEnablePrereleaseUpdates"
    static let allowedPreReleaseChannels: Set<String> = ["beta", "prerelease", "pre-release", "rc"]

    static func releaseMetadata(currentVersion: String, newVersion: String) -> BourbonReleaseMetadata {
        BourbonReleaseMetadata(
            currentVersion: currentVersion,
            newVersion: newVersion,
            kind: releaseKind(currentVersion: currentVersion, newVersion: newVersion),
            isPreRelease: isPreRelease(newVersion)
        )
    }

    static func releaseKind(currentVersion: String, newVersion: String) -> BourbonReleaseKind {
        if isMajorUpdate(currentVersion, newVersion) {
            return .major
        }

        if isEmergencyUpdate(currentVersion, newVersion) {
            return .emergency
        }

        if isMinorUpdate(currentVersion, newVersion) {
            return .minor
        }

        if isPatchUpdate(currentVersion, newVersion) {
            return .patch
        }

        return .unknown
    }

    static func isMajorUpdate(_ currentVersion: String, _ newVersion: String) -> Bool {
        guard let current = BourbonUpdateVersion(currentVersion),
              let new = BourbonUpdateVersion(newVersion) else {
            return false
        }

        return new.major > current.major
    }

    static func isEmergencyUpdate(_ currentVersion: String, _ newVersion: String) -> Bool {
        guard let current = BourbonUpdateVersion(currentVersion),
              let new = BourbonUpdateVersion(newVersion),
              new.major == current.major else {
            return false
        }

        return new.normalMinor == current.normalMinor &&
        new.emergencyLevel > current.emergencyLevel
    }

    static func isMinorUpdate(_ currentVersion: String, _ newVersion: String) -> Bool {
        guard let current = BourbonUpdateVersion(currentVersion),
              let new = BourbonUpdateVersion(newVersion),
              new.major == current.major else {
            return false
        }

        return new.normalMinor > current.normalMinor
    }

    static func isPatchUpdate(_ currentVersion: String, _ newVersion: String) -> Bool {
        guard let current = BourbonUpdateVersion(currentVersion),
              let new = BourbonUpdateVersion(newVersion),
              new.major == current.major,
              new.normalMinor == current.normalMinor,
              new.emergencyLevel == current.emergencyLevel else {
            return false
        }

        return new.patch > current.patch
    }

    static func isPreRelease(_ version: String) -> Bool {
        BourbonUpdateVersion(version)?.isPreRelease ?? false
    }

    static func isPreReleaseChannel(_ channel: String?) -> Bool {
        guard let channel else {
            return false
        }

        return allowedPreReleaseChannels.contains(channel.lowercased())
    }

    static var preReleaseUpdatesEnabled: Bool {
        UserDefaults.standard.bool(forKey: preReleaseUpdatesEnabledKey)
    }

    static var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}

final class BourbonSparkleVersionDisplayer: NSObject, SUVersionDisplay {
    func formatUpdateVersion(
        fromUpdate update: SUAppcastItem,
        andBundleDisplayVersion inOutBundleDisplayVersion: AutoreleasingUnsafeMutablePointer<NSString>,
        withBundleVersion bundleVersion: String
    ) -> String {
        let publicBundleVersion = String(inOutBundleDisplayVersion.pointee)
        inOutBundleDisplayVersion.pointee = publicBundleVersion as NSString
        return update.displayVersionString
    }

    func formatBundleDisplayVersion(
        _ bundleDisplayVersion: String,
        withBundleVersion bundleVersion: String,
        matchingUpdate update: SUAppcastItem?
    ) -> String {
        bundleDisplayVersion
    }
}

final class BourbonUpdatePolicyDelegate: NSObject, SPUUpdaterDelegate {
    private let versionDisplayer = BourbonSparkleVersionDisplayer()

    func versionDisplayer(for updater: SPUUpdater) -> (any SUVersionDisplay)? {
        versionDisplayer
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        BourbonUpdatePolicy.preReleaseUpdatesEnabled ? BourbonUpdatePolicy.allowedPreReleaseChannels : []
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let metadata = BourbonUpdatePolicy.releaseMetadata(
            currentVersion: BourbonUpdatePolicy.currentAppVersion,
            newVersion: item.displayVersionString
        )
        print(
            """
            Bourbon update policy:
            current=\(metadata.currentVersion)
            available=\(metadata.newVersion)
            kind=\(metadata.kind.rawValue)
            preRelease=\(metadata.isPreRelease)
            sparkleMajorUpgrade=\(item.isMajorUpgrade)
            sparkleCriticalUpdate=\(item.isCriticalUpdate)
            channel=\(item.channel ?? "default")
            """
        )

        if metadata.kind == .major && !item.isMajorUpgrade {
            // Sparkle enforces manual confirmation for appcast items marked as
            // major upgrades. The release workflow now writes
            // sparkle:minimumAutoupdateVersion so Sparkle can make this
            // decision before downloading. This fallback keeps accidental
            // unmarked major releases from silently installing.
            updater.automaticallyDownloadsUpdates = false
        }
    }

    func updater(
        _ updater: SPUUpdater,
        shouldProceedWithUpdate updateItem: SUAppcastItem,
        updateCheck: SPUUpdateCheck
    ) throws {
        let isPreRelease = BourbonUpdatePolicy.isPreRelease(updateItem.displayVersionString) ||
        BourbonUpdatePolicy.isPreRelease(updateItem.versionString) ||
        BourbonUpdatePolicy.isPreReleaseChannel(updateItem.channel)

        if isPreRelease && !BourbonUpdatePolicy.preReleaseUpdatesEnabled {
            throw NSError(
                domain: "com.unblockerfire.Bourbon.updates",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Pre-release Bourbon updates are disabled. Enable them in Settings to receive this build."
                ]
            )
        }
    }
}

struct SparkleView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("check.updates", action: updater.checkForUpdates)
            .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

// This view model class publishes when new updates can be checked by the user
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

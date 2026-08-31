//
//  AppDelegate.swift
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
import OSLog
import ServiceManagement
import SwiftUI
import WhiskyKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        // Test if automatic window tabbing is enabled
        // as it is disabled when ContentView appears
        if NSWindow.allowsAutomaticWindowTabbing, let url = urls.first {
            // Reopen the file after Whisky has been opened
            // so that the `onOpenURL` handler is actually called
            NSWorkspace.shared.open(url)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        BourbonLaunchContextDiagnostics.record(notification: notification)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            BourbonInstallationGuard.runLaunchChecks()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if UserDefaults.standard.bool(forKey: "killOnTerminate") {
            WhiskyApp.killBottles()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

}

@MainActor
private enum BourbonLaunchContextDiagnostics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Bourbon",
        category: "LaunchLifecycle"
    )

    // swiftlint:disable:next function_body_length
    static func record(notification: Notification) {
        let userInfo = notification.userInfo
        let loginItemLaunch = boolValue(userInfo, key: "NSApplicationLaunchIsLoginItemKey")
        let sessionRestoreLaunch = boolValue(userInfo, key: "NSApplicationLaunchIsSessionRestoreKey")
        let defaultLaunch = boolValue(userInfo, key: "NSApplicationLaunchIsDefaultLaunchKey")
        let launchReason = reason(
            loginItem: loginItemLaunch,
            sessionRestore: sessionRestoreLaunch,
            defaultLaunch: defaultLaunch
        )
        let loginStatus = loginItemStatusName(SMAppService.mainApp.status)
        let embeddedLoginItems = FileManager.default.fileExists(
            atPath: Bundle.main.bundleURL
                .appendingPathComponent("Contents/Library/LoginItems", isDirectory: true)
                .path
        )
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "unknown"
        let isDiagnostic = bundleIdentifier == "com.unblockerfire.BourbonDiagnostic"

        let detail = [
            "reason=\(launchReason)",
            "login_item_launch=\(loginItemLaunch)",
            "session_restore=\(sessionRestoreLaunch)",
            "default_launch=\(defaultLaunch)",
            "smapp_status=\(loginStatus)",
            "embedded_login_items=\(embeddedLoginItems)",
            "diagnostic=\(isDiagnostic)"
        ].joined(separator: " ")
        logger.notice("app.launch.context \(detail, privacy: .public)")
        print("app.launch.context \(detail)")
    }

    private static func boolValue(_ userInfo: [AnyHashable: Any]?, key: String) -> Bool {
        if let value = userInfo?[key] as? NSNumber {
            return value.boolValue
        }
        return userInfo?[key] as? Bool ?? false
    }

    private static func reason(loginItem: Bool, sessionRestore: Bool, defaultLaunch: Bool) -> String {
        if loginItem {
            return "login_item"
        }
        if sessionRestore {
            return "session_restore"
        }
        if defaultLaunch {
            return "default"
        }
        return "unspecified"
    }

    private static func loginItemStatusName(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered:
            return "not_registered"
        case .enabled:
            return "enabled"
        case .requiresApproval:
            return "requires_approval"
        case .notFound:
            return "not_found"
        @unknown default:
            return "unknown"
        }
    }
}

private enum BourbonInstallationGuard {
    private static let appName = "Bourbon.app"
    private static let maxDisplayedPaths = 8

    @MainActor
    static func runLaunchChecks() {
        guard !isRunningFromDevelopmentBuild else { return }
        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        guard !DiagnosticAppInstallationPolicy.isDiagnosticBuild(displayName: displayName) else { return }

        if isRunningFromMountedInstaller {
            showMountedInstallerAlert()
        }

        let copies = findInstalledCopies()
        guard copies.count > 1,
              let currentCopy = copies.first(where: { isCurrentApp($0.url) }) else {
            return
        }

        let newestCopy = copies.max { lhs, rhs in
            lhs.version < rhs.version
        }

        if let newestCopy, !isCurrentApp(newestCopy.url), newestCopy.version > currentCopy.version {
            showCurrentAppIsOlderAlert(newestCopy: newestCopy, copies: copies)
            return
        }

        let oldCopies = copies
            .filter { !isCurrentApp($0.url) }
            .filter { $0.version < currentCopy.version || $0.version == currentCopy.version }

        if !oldCopies.isEmpty {
            showDuplicateCopiesAlert(oldCopies: oldCopies)
        }
    }

    private static var currentAppURL: URL {
        Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
    }

    private static var isRunningFromDevelopmentBuild: Bool {
        let path = currentAppURL.path
        return path.contains("/DerivedData/") || path.contains("/Build/Products/")
    }

    private static var isRunningFromMountedInstaller: Bool {
        currentAppURL.path.hasPrefix("/Volumes/")
    }

    private static func isCurrentApp(_ url: URL) -> Bool {
        url.resolvingSymlinksInPath().standardizedFileURL.path == currentAppURL.path
    }

    @MainActor
    private static func showMountedInstallerAlert() {
        let alert = NSAlert()
        alert.messageText = "Bourbon is currently running from the installer."
        alert.informativeText = """
        To receive automatic updates and the best experience, drag Bourbon into your Applications folder before
        using it.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Applications")
        alert.addButton(withTitle: "Reveal Installer")
        alert.addButton(withTitle: "Continue Anyway")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        case .alertSecondButtonReturn:
            NSWorkspace.shared.activateFileViewerSelecting([currentAppURL])
        default:
            break
        }
    }

    @MainActor
    private static func showCurrentAppIsOlderAlert(newestCopy: BourbonAppCopy, copies: [BourbonAppCopy]) {
        let alert = NSAlert()
        alert.messageText = "A newer copy of Bourbon is installed."
        alert.informativeText = """
        You are running an older copy of Bourbon. Opening older copies can make Bourbon look outdated or broken.

        Newest copy:
        \(newestCopy.url.path)

        Other detected copies:
        \(pathsText(for: copies.filter { !isCurrentApp($0.url) }))
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Newest Bourbon")
        alert.addButton(withTitle: "Reveal in Finder")
        alert.addButton(withTitle: "Later")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(newestCopy.url)
            NSApp.terminate(nil)
        case .alertSecondButtonReturn:
            NSWorkspace.shared.activateFileViewerSelecting([newestCopy.url])
        default:
            break
        }
    }

    @MainActor
    private static func showDuplicateCopiesAlert(oldCopies: [BourbonAppCopy]) {
        let alert = NSAlert()
        alert.messageText = "We found older copies of Bourbon that could cause confusion."
        alert.informativeText = """
        Opening an older copy can make Bourbon look outdated or broken.

        Detected older copies:
        \(pathsText(for: oldCopies))

        Bourbon will only move old Bourbon.app copies to Trash. Your bottles, licenses, settings, and app data
        are not touched.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Remove Old Copies")
        alert.addButton(withTitle: "Reveal in Finder")
        alert.addButton(withTitle: "Later")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            moveOldCopiesToTrash(oldCopies)
        case .alertSecondButtonReturn:
            NSWorkspace.shared.activateFileViewerSelecting(oldCopies.map(\.url))
        default:
            break
        }
    }

    @MainActor
    private static func moveOldCopiesToTrash(_ copies: [BourbonAppCopy]) {
        let failedCopies = copies.compactMap { copy -> URL? in
            guard !isCurrentApp(copy.url) else { return nil }

            do {
                var trashedURL: NSURL?
                try FileManager.default.trashItem(at: copy.url, resultingItemURL: &trashedURL)
                return nil
            } catch {
                print("Failed to move old Bourbon copy to Trash: \(copy.url.path)")
                return copy.url
            }
        }

        if failedCopies.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Old copies moved to Trash."
            alert.informativeText = "Bourbon kept the app you are currently using and did not touch your data."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } else {
            let alert = NSAlert()
            alert.messageText = "Some old copies could not be removed."
            alert.informativeText = """
            macOS would not allow Bourbon to move these copies to Trash:

            \(failedCopies.map(\.path).joined(separator: "\n"))
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Reveal in Finder")
            alert.addButton(withTitle: "Later")

            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting(failedCopies)
            }
        }
    }

    private static func pathsText(for copies: [BourbonAppCopy]) -> String {
        let visiblePaths = copies.prefix(maxDisplayedPaths).map { $0.url.path }
        let extraCount = max(0, copies.count - maxDisplayedPaths)
        let extraText = extraCount > 0 ? "\n...and \(extraCount) more." : ""
        return visiblePaths.joined(separator: "\n") + extraText
    }

    private static func findInstalledCopies() -> [BourbonAppCopy] {
        let roots = scanRoots()
        var copies: [String: BourbonAppCopy] = [:]

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            for url in findBourbonApps(under: root) {
                guard let copy = BourbonAppCopy(url: url) else { continue }
                copies[url.resolvingSymlinksInPath().standardizedFileURL.path] = copy
            }
        }

        if let currentCopy = BourbonAppCopy(url: currentAppURL) {
            copies[currentAppURL.path] = currentCopy
        }

        return Array(copies.values).sorted { $0.url.path < $1.url.path }
    }

    private static func scanRoots() -> [URL] {
        var roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Volumes"),
            URL(fileURLWithPath: "/private/tmp"),
            URL(fileURLWithPath: NSTemporaryDirectory())
        ]

        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        roots.append(home.appendingPathComponent("Applications"))
        roots.append(home.appendingPathComponent("Downloads"))
        roots.append(home.appendingPathComponent("Library").appendingPathComponent("Caches"))

        return roots
    }

    private static func findBourbonApps(under root: URL) -> [URL] {
        if root.lastPathComponent == appName {
            return [root]
        }

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else {
            return []
        }

        var matches: [URL] = []

        for case let url as URL in enumerator {
            let depth = url.pathComponents.count - root.pathComponents.count
            if depth > maxScanDepth(for: root) {
                enumerator.skipDescendants()
                continue
            }

            if url.lastPathComponent == appName {
                matches.append(url)
                enumerator.skipDescendants()
            }
        }

        return matches
    }

    private static func maxScanDepth(for root: URL) -> Int {
        switch root.path {
        case "/Applications", "/Volumes":
            return 3
        case "/private/tmp":
            return 4
        default:
            return 3
        }
    }
}

private struct BourbonAppCopy {
    let url: URL
    let version: BourbonAppVersion

    init?(url: URL) {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any],
              let bundleIdentifier = info["CFBundleIdentifier"] as? String,
              bundleIdentifier == "com.unblockerfire.Bourbon" else {
            return nil
        }

        let shortVersion = info["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info["CFBundleVersion"] as? String ?? "0"

        self.url = url
        self.version = BourbonAppVersion(shortVersion: shortVersion, build: build)
    }
}

private struct BourbonAppVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int
    let isPreRelease: Bool
    let build: Int

    init(shortVersion: String, build: String) {
        let lowercasedVersion = shortVersion.lowercased()
        let coreVersion = lowercasedVersion.split(separator: "-").first.map(String.init) ?? shortVersion
        let parts = coreVersion.split(separator: ".").map { Int($0) ?? 0 }

        self.major = parts.indices.contains(0) ? parts[0] : 0
        self.minor = parts.indices.contains(1) ? parts[1] : 0
        self.patch = parts.indices.contains(2) ? parts[2] : 0
        self.isPreRelease = lowercasedVersion.contains("pre") ||
            lowercasedVersion.contains("beta") ||
            lowercasedVersion.contains("rc")
        self.build = Int(build) ?? 0
    }

    static func < (lhs: BourbonAppVersion, rhs: BourbonAppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.isPreRelease != rhs.isPreRelease { return lhs.isPreRelease && !rhs.isPreRelease }
        return lhs.build < rhs.build
    }
}

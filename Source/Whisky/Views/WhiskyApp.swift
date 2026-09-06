//  WhiskyApp.swift
//
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
import AppKit
import Sparkle
import WhiskyKit

@main
struct WhiskyApp: App {
    @State var showSetup: Bool = false
    @StateObject private var diagnosticInstaller = DiagnosticInstallationCoordinator()
    @AppStorage("hasCompletedFirstRunOnboarding") private var hasCompletedFirstRunOnboarding = false
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openURL) var openURL
    private let updatePolicyDelegate: BourbonUpdatePolicyDelegate
    private let updateUserDriver: BourbonPendingUpdateUserDriver
    private let updater: SPUUpdater

    init() {
        Wine.logCustomWineStartupEnvironment()
        let updatePolicyDelegate = BourbonUpdatePolicyDelegate()
        let updateUserDriver = BourbonPendingUpdateUserDriver(
            hostBundle: .main,
            pendingUpdateManager: .shared
        )
        self.updatePolicyDelegate = updatePolicyDelegate
        self.updateUserDriver = updateUserDriver
        self.updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: updateUserDriver,
            delegate: updatePolicyDelegate
        )

        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        if !DiagnosticAppInstallationPolicy.isDiagnosticBuild(displayName: displayName) {
            do {
                try updater.start()
            } catch {
                print("Failed to start Bourbon updater: \(error.localizedDescription)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if diagnosticInstaller.requiresSetup {
                    DiagnosticAppInstallerView(coordinator: diagnosticInstaller)
                } else {
                    mainContent
                }
            }
            .preferredColorScheme(.dark)
            .background(BourbonWindowAppearance())
        }
        // Don't ask me how this works, it just does
        .handlesExternalEvents(matching: ["{same path of URL?}"])
        .commands {
            CommandGroup(after: .appInfo) {
                SparkleView(updater: updater)
                if isDiagnosticBuild {
                    Divider()
                    Button("Copy Diagnostic UI Report") {
                        BourbonWindowHierarchyDiagnostics.copyCurrentReport(stage: "menu_command")
                    }
                    .keyboardShortcut("D", modifiers: [.command, .shift])
                }
            }
            CommandGroup(before: .systemServices) {
                Divider()
                Button("open.setup") {
                    showSetup = true
                }
                Button("install.cli") {
                    Task {
                        await WhiskyCmd.install()
                    }
                }
            }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("open.bottle") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = false
                    panel.begin { result in
                        if result == .OK {
                            if let url = panel.urls.first {
                                BottleVM.shared.bottlesList.paths.append(url)
                                BottleVM.shared.loadBottles()
                            }
                        }
                    }
                }
                .keyboardShortcut("I", modifiers: [.command])
            }
            CommandGroup(after: .importExport) {
                Button("open.logs") {
                    WhiskyApp.openLogsFolder()
                }
                .keyboardShortcut("L", modifiers: [.command])
                Button("kill.bottles") {
                    WhiskyApp.killBottles()
                }
                .keyboardShortcut("K", modifiers: [.command, .shift])
                Button("wine.clearShaderCaches") {
                    WhiskyApp.killBottles() // Better not make things more complicated for ourselves
                    WhiskyApp.wipeShaderCaches()
                }
            }
            CommandGroup(replacing: .help) {
                Button("Report a Problem") {
                    BourbonReportCenter.openReport()
                }
                Button("help.website") {
                    if let url = URL(string: "https://getbourbon.app/") {
                        openURL(url)
                    }
                }
                Button("help.github") {
                    if let url = URL(string: "https://github.com/Bourbon-App/Bourbon") {
                        openURL(url)
                    }
                }
                Button("help.discord") {
                    if let url = URL(string: BourbonSupport.discordURL) {
                        openURL(url)
                    }
                }
            }
        }
        Settings {
            if diagnosticInstaller.requiresSetup {
                Text("Finish moving Bourbon Diagnostic to Applications to open settings.")
                    .padding(28)
            } else {
                SettingsView()
            }
        }
    }

    private var isDiagnosticBuild: Bool {
        Bundle.main.bundleIdentifier == BourbonLicenseStoragePolicy.diagnosticBundleIdentifier
    }

    private var mainContent: some View {
        ContentView(showSetup: $showSetup, updater: updater)
            .frame(minWidth: ViewWidth.large, minHeight: 316)
            .environmentObject(BottleVM.shared)
            .onAppear {
                NSWindow.allowsAutomaticWindowTabbing = false
                Task { @MainActor in
                    BourbonAdminServicesMenuController.shared.installAdminLoginItem()
                }
                BourbonReportCenter.startListeningForReportRequests()
                if !hasCompletedFirstRunOnboarding { showSetup = true }
                Task.detached { await WhiskyApp.deleteOldLogs() }
                BourbonReportCenter.promptForRecentCrashIfNeeded()
            }
    }

    static func killBottles() {
        for bottle in BottleVM.shared.bottles {
            do {
                try Wine.killBottle(bottle: bottle)
            } catch {
                print("Failed to kill bottle: \(error)")
            }
        }
    }

    static func openLogsFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Wine.logsFolder.path)
    }

    static func deleteOldLogs() {
        let pastDate = Date().addingTimeInterval(-7 * 24 * 60 * 60)

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: Wine.logsFolder,
            includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }

        let logs = urls.filter { url in
            url.pathExtension == "log"
        }

        let oldLogs = logs.filter { url in
            do {
                let resourceValues = try url.resourceValues(forKeys: [.creationDateKey])

                return resourceValues.creationDate ?? Date() < pastDate
            } catch {
                return false
            }
        }

        for log in oldLogs {
            do {
                try FileManager.default.removeItem(at: log)
            } catch {
                print("Failed to delete log: \(error)")
            }
        }
    }

    static func wipeShaderCaches() {
        let getconf = Process()
        getconf.executableURL = URL(fileURLWithPath: "/usr/bin/getconf")
        getconf.arguments = ["DARWIN_USER_CACHE_DIR"]
        let pipe = Pipe()
        getconf.standardOutput = pipe
        do {
            try getconf.run()
        } catch {
            return
        }
        getconf.waitUntilExit()
        let getconfOutput = {() -> Data in
            if #available(macOS 10.15, *) {
                do {
                    return try pipe.fileHandleForReading.readToEnd() ?? Data()
                } catch {
                    return Data()
                }
            } else {
                return pipe.fileHandleForReading.readDataToEndOfFile()
            }
        }()
        guard let getconfOutputString = String(data: getconfOutput, encoding: .utf8) else {return}
        let d3dmPath = URL(fileURLWithPath: getconfOutputString.trimmingCharacters(in: .whitespacesAndNewlines))
            .appending(path: "d3dm").path
        do {
            try FileManager.default.removeItem(atPath: d3dmPath)
        } catch {
            return
        }
    }
}

/// SwiftUI's preferred color scheme does not always reach AppKit's split-view
/// chrome on a Light-mode host. Keep Bourbon's own windows in dark Aqua.
private struct BourbonWindowAppearance: NSViewRepresentable {
    func makeNSView(context: Context) -> AppearanceView { AppearanceView() }

    func updateNSView(_ nsView: AppearanceView, context: Context) {
        nsView.applyBourbonAppearance()
    }

    final class AppearanceView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyBourbonAppearance()
        }

        func applyBourbonAppearance() {
            window?.appearance = NSAppearance(named: .darkAqua)
            window?.backgroundColor = NSColor(calibratedRed: 0.027, green: 0.023, blue: 0.02, alpha: 1)
        }
    }
}

@MainActor
private final class BourbonAdminServicesMenuController: NSObject {
    static let shared = BourbonAdminServicesMenuController()

    private let menuMarker = "com.unblockerfire.Bourbon.admin-services-menu.adlg"

    /// Supported admin entry point: Bourbon > Services > ADLG.
    func installAdminLoginItem() {
        configureServicesMenu()
    }

    private func configureServicesMenu() {
        guard let servicesMenu = NSApp.servicesMenu ?? appServicesMenu() else { return }
        guard !servicesMenu.items.contains(where: { $0.representedObject as? String == menuMarker }) else {
            return
        }

        let item = NSMenuItem(
            title: "ADLG",
            action: #selector(openAdminLogin),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = menuMarker
        item.toolTip = "Open Admin Login"

        servicesMenu.addItem(item)
    }

    private func appServicesMenu() -> NSMenu? {
        NSApp.mainMenu?
            .items
            .first?
            .submenu?
            .item(withTitle: "Services")?
            .submenu
    }

    @objc private func openAdminLogin() {
        NotificationCenter.default.post(name: .bourbonOpenAdminLogin, object: nil)
    }
}

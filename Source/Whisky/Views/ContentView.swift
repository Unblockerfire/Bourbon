//  ContentView.swift
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
import UniformTypeIdentifiers
import WhiskyKit
import SemanticVersion
import Sparkle

// swiftlint:disable file_length

extension Notification.Name {
    static let bourbonOpenAdminLogin = Notification.Name("BourbonOpenAdminLogin")
}

/// The runtime-update sheet payload is its presentation state.  SwiftUI never
/// receives a request to present this sheet without the version it needs to render.
private struct BourbonWineRuntimeUpdatePresentation: Identifiable {
    let version: SemanticVersion

    var id: String { String(describing: version) }
}

@MainActor
enum BourbonSheetDiagnostics {
    enum Source: String {
        case sparklePendingUpdate = "sparkle_pending_update"
        case adminUnlock = "admin_unlock"
        case bourbonWineRuntimeUpdate = "bourbon_wine_runtime_update"
        case fileOpen = "file_open"
        case bottleExplanation = "bottle_explanation"
    }

    static func recordPresentation(source: Source) {
        record("sheet.present", source: source)
        DispatchQueue.main.async {
            record("sheet.present", source: source)
        }
    }

    static func recordDismissal(source: Source) {
        record("sheet.dismiss", source: source)
    }

    private static func record(_ event: String, source: Source) {
        let keyWindow = NSApp.keyWindow
        BourbonLicenseDiagnostics.record(
            event,
            detail: "source=\(source.rawValue) window=\(keyWindow?.windowNumber ?? -1) " +
                "class=\(keyWindow.map { String(describing: type(of: $0)) } ?? \"none\") " +
                "attached_sheet=\(keyWindow?.attachedSheet != nil)"
        )
    }
}

// swiftlint:disable:next type_body_length
struct ContentView: View {
    @AppStorage("selectedBottleURL") private var selectedBottleURL: URL?
    @AppStorage("hasCompletedFirstRunOnboarding") private var hasCompletedFirstRunOnboarding = false
    @AppStorage("hasDismissedLegacyWineWarning") private var hasDismissedLegacyWineWarning = false
    @AppStorage("displayName") private var displayName = ""
    @EnvironmentObject var bottleVM: BottleVM
    @ObservedObject private var installManager = InstallManager.shared
    @ObservedObject private var pendingUpdateManager = BourbonPendingUpdateManager.shared
    @Binding var showSetup: Bool
    let updater: SPUUpdater

    @State private var selected: URL?
    @State private var showBottleCreation: Bool = false
    @State private var showBottleSelection: Bool = false
    @State private var newlyCreatedBottleURL: URL?
    @State private var firstInstallBottleURL: URL?
    @State private var firstInstallerURL: URL?
    @State private var activePage: MainContentPage? = .home
    @State private var openedFileURL: URL?
    @State private var triggerRefresh: Bool = false
    @State private var refreshAnimation: Angle = .degrees(0)
    @State private var homeSubtitle = BourbonHomeCopy.randomSubtitle()
    @State private var showAdminUnlock = false
    @State private var previousPageBeforeCreation: MainContentPage? = .home
    // A sheet must have one authoritative presentation value. Keeping a Bool
    // separate from the optional version allowed SwiftUI to create a sheet with
    // an EmptyView while no update payload was available.
    @State private var runtimeUpdatePresentation: BourbonWineRuntimeUpdatePresentation?
    @State private var resolvedAccountLicense: BourbonLicenseRecord?

    @State private var bottleFilter = ""

    var body: some View {
        Group {
            if usesStandalonePresentation {
                NavigationStack {
                    detail
                }
            } else {
                appSidebarShell
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .overlay(alignment: .bottomTrailing) {
            if !usesStandalonePresentation {
                GlobalInstallStatusBanner(manager: installManager)
                    .padding()
            }
        }
        .overlay(alignment: .top) {
            if pendingUpdateManager.isPending &&
                !pendingUpdateManager.isPromptPresented &&
                !usesStandalonePresentation {
                BourbonPendingUpdatePill(manager: pendingUpdateManager)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $pendingUpdateManager.isPromptPresented, onDismiss: {
            BourbonSheetDiagnostics.recordDismissal(source: .sparklePendingUpdate)
        }, content: {
            BourbonPendingUpdatePrompt(manager: pendingUpdateManager, updater: updater)
                .onAppear {
                    BourbonSheetDiagnostics.recordPresentation(source: .sparklePendingUpdate)
                }
        })
        .sheet(isPresented: $showAdminUnlock, onDismiss: {
            BourbonSheetDiagnostics.recordDismissal(source: .adminUnlock)
        }, content: {
            AdminUnlockView()
                .onAppear {
                    BourbonSheetDiagnostics.recordPresentation(source: .adminUnlock)
                }
        })
        .sheet(item: $runtimeUpdatePresentation, onDismiss: {
            BourbonSheetDiagnostics.recordDismissal(source: .bourbonWineRuntimeUpdate)
        }, content: { presentation in
            BourbonWineRuntimeUpdateView(availableVersion: presentation.version) {
                runtimeUpdatePresentation = nil
            }
            .onAppear {
                BourbonSheetDiagnostics.recordPresentation(source: .bourbonWineRuntimeUpdate)
            }
        })
        .onReceive(NotificationCenter.default.publisher(for: .bourbonOpenAdminLogin)) { _ in
            openAdminLogin()
        }
        .toolbar {
            if !usesStandalonePresentation {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        updater.checkForUpdates()
                    } label: {
                        Label("Check for Updates", systemImage: "arrow.down.circle")
                    }
                    .help("Check for Bourbon updates.")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        selected = nil
                        activePage = .account
                    } label: {
                        Label("Account", systemImage: "person.crop.circle")
                    }
                    .help("View your Bourbon account.")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openBottleCreation()
                    } label: {
                        Image(systemName: "plus")
                            .help("button.createBottle")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        bottleVM.loadBottles()
                        if let bottle = bottleVM.bottles.first(where: { $0.url == selected }) {
                            bottle.updateInstalledPrograms()
                        }
                        triggerRefresh.toggle()
                        withAnimation(.default) {
                            refreshAnimation = .degrees(360)
                        } completion: {
                            refreshAnimation = .degrees(0)
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .help("button.refresh")
                            .rotationEffect(refreshAnimation)
                    }
                }
            }
        }
        .sheet(item: $openedFileURL, onDismiss: {
            BourbonSheetDiagnostics.recordDismissal(source: .fileOpen)
        }, content: { url in
            FileOpenView(fileURL: url,
                         currentBottle: selected,
                         bottles: bottleVM.bottles)
                .onAppear {
                    BourbonSheetDiagnostics.recordPresentation(source: .fileOpen)
                }
        })
        .onChange(of: selected) {
            if selected != nil {
                print("bottle.selection.changed")
            }
            selectedBottleURL = selected
        }
        .onChange(of: showSetup) { _, isPresented in
            if isPresented {
                selected = nil
                showBottleCreation = false
                activePage = .setup
            } else if activePage == .setup {
                activePage = .home
            }
        }
        .onChange(of: showBottleCreation) { _, isPresented in
            if isPresented && activePage != .createBottle {
                previousPageBeforeCreation = activePage
                selected = nil
                showSetup = false
                activePage = .createBottle
            } else if activePage == .createBottle {
                activePage = previousPageBeforeCreation ?? .home
            }
        }
        .handlesExternalEvents(preferring: [], allowing: ["*"])
        .onOpenURL { url in
            openedFileURL = url
        }
        .task {
            print("bottle.list.refresh.started")
            bottleVM.loadBottles()
            print("bottle.list.refresh.completed")

            WhiskyWineInstaller.recordRuntimeEvent("runtime.bootstrap.content_check.started")
            let runtimeReadiness = await Task.detached(priority: .userInitiated) {
                WhiskyWineInstaller.runtimeReadiness(in: WhiskyWineInstaller.applicationFolder)
            }.value
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.bootstrap.content_check.completed",
                detail: "ready=\(runtimeReadiness.isReady)"
            )
            if !runtimeReadiness.isReady {
                WhiskyWineInstaller.recordRuntimeEvent(
                    "runtime.install.required",
                    detail: "reason=readiness_failed"
                )
                WhiskyWineInstaller.recordRuntimeEvent(
                    "runtime.install.destination",
                    detail: "bundle_identifier=\(Bundle.whiskyBundleIdentifier)"
                )
                showSetup = true
            }

            if let legacyMarker = WhiskyWineInstaller.legacyRuntimeMarkerURL(),
               !hasDismissedLegacyWineWarning {
                showLegacyRuntimeWarning(markerURL: legacyMarker)
            }

            let task = Task.detached {
                return await WhiskyWineInstaller.shouldUpdateWhiskyWine()
            }
            let updateInfo = await task.value
            if updateInfo.0, !showSetup {
                runtimeUpdatePresentation = BourbonWineRuntimeUpdatePresentation(version: updateInfo.1)
            } else if updateInfo.0 {
                BourbonLicenseDiagnostics.record(
                    "sheet.not_presented",
                    detail: "source=bourbon_wine_runtime_update reason=setup_active"
                )
            }

            resolvedAccountLicense = await LicenseKeychainStore.currentLicenseAsync()
        }
    }

    private var usesStandalonePresentation: Bool {
        activePage == .setup || activePage == .createBottle || firstInstallBottleURL != nil
    }

    @ViewBuilder
    private var appSidebarShell: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 260)
                .background(.regularMaterial)

            Divider()

            NavigationStack {
                detail
            }
        }
    }

    private func openBottleCreation() {
        BottleCreationDiagnostics.record("bottle.create.button.clicked")
        BottleCreationDiagnostics.record("bottle.create.view.opened")
        previousPageBeforeCreation = activePage
        selected = nil
        newlyCreatedBottleURL = nil
        firstInstallerURL = nil
        showSetup = false
        showBottleCreation = true
        activePage = .createBottle
    }

    private func openHome() {
        selected = nil
        showSetup = false
        showBottleCreation = false
        firstInstallBottleURL = nil
        activePage = .home
    }

    private func openDistillery() {
        selected = nil
        showSetup = false
        showBottleCreation = false
        firstInstallBottleURL = nil
        activePage = .library
    }

    private func openAdminLogin() {
        showAdminUnlock = true
    }

    private func showLegacyRuntimeWarning(markerURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Older Wine Runner Detected"
        alert.informativeText = """
        Bourbon found an older BourbonWine runtime marker at:
        \(markerURL.lastPathComponent)

        For the best BourbonWine compatibility, remove the old runner and install BourbonWine again.
        """
        alert.alertStyle = .warning
        let removeButton = alert.addButton(withTitle: "Remove Old Runtime")
        removeButton.hasDestructiveAction = true
        alert.addButton(withTitle: "Keep for Now")

        if alert.runModal() == .alertFirstButtonReturn {
            WhiskyWineInstaller.uninstall()
            showSetup = true
        } else {
            hasDismissedLegacyWineWarning = true
        }
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("Search bottles", text: $bottleFilter)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.09), lineWidth: 1)
                }
                .help("Search your bottles.")

                VStack(spacing: 4) {
                    SidebarPageButton(
                        title: "Home",
                        systemImage: "house",
                        isActive: activePage == .home
                    ) {
                            openHome()
                    }
                    .help("Go to Bourbon Home.")

                    SidebarPageButton(
                        title: "🥃 Distillery",
                        systemImage: "books.vertical",
                        isActive: activePage == .library
                    ) {
                        openDistillery()
                    }
                    .help("Browse games and apps.")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .padding(.top, sidebarTitlebarInset)

            Divider()

            List(selection: $selected) {
                    Section {
                        ForEach(filteredBottles) { bottle in
                            Group {
                                if bottle.inFlight {
                                    HStack {
                                        Text(bottle.settings.name)
                                        Spacer()
                                        ProgressView().controlSize(.small)
                                    }
                                    .opacity(0.5)
                                } else {
                                    BottleListEntry(bottle: bottle, selected: $selected, refresh: $triggerRefresh)
                                        .selectionDisabled(!bottle.isAvailable)
                                }
                            }
                            .id(bottle.url)
                        }
                    }
                }
                .animation(.default, value: bottleVM.bottles)
                .animation(.default, value: bottleFilter)
                .listStyle(.sidebar)
                .onChange(of: selected) {
                    if selected != nil {
                        activePage = nil
                    }
            }
        }
    }

    @ViewBuilder
    var detail: some View {
        if activePage == .home {
            BourbonHomeView(
                bottles: bottleVM.bottles,
                displayName: resolvedDisplayName,
                subtitle: homeSubtitle,
                createBottle: {
                    openBottleCreation()
                },
                openBottle: { bottle in
                    selected = bottle.url
                    activePage = nil
                }
            )
        } else if activePage == .library {
            DistilleryView()
        } else if activePage == .account {
            AccountPageView(displayName: resolvedDisplayName, license: accountLicense)
        } else if activePage == .setup {
            SetupView(
                showSetup: $showSetup,
                showBottleCreation: $showBottleCreation,
                updater: updater,
                firstTime: !hasCompletedFirstRunOnboarding
            )
        } else if activePage == .createBottle {
            BottleCreationView(
                newlyCreatedBottleURL: $newlyCreatedBottleURL,
                selectedInstallerURL: $firstInstallerURL,
                cancel: {
                    showBottleCreation = false
                },
                created: { url in
                    BottleCreationDiagnostics.record("bottle.create.selection.started")
                    selected = url
                    selectedBottleURL = url
                    firstInstallBottleURL = firstInstallerURL == nil ? nil : url
                    BottleCreationDiagnostics.record("bottle.create.selection.completed")
                    BottleCreationDiagnostics.record("bottle.create.completed")
                    activePage = nil
                    showBottleCreation = false
                }
            )
        } else if let firstInstallBottleURL,
                  let bottle = bottleVM.bottles.first(where: { $0.url == firstInstallBottleURL }) {
            FirstInstallView(bottle: bottle, initialInstallerURL: firstInstallerURL) {
                self.firstInstallerURL = nil
                self.firstInstallBottleURL = nil
                activePage = nil
            }
        } else if let bottle = selected {
            if let bottle = bottleVM.bottles.first(where: { $0.url == bottle }) {
                BottleView(bottle: bottle)
                    .disabled(bottle.inFlight)
                    .id(bottle.url)
            }
        } else {
            BourbonHomeView(
                bottles: bottleVM.bottles,
                displayName: resolvedDisplayName,
                subtitle: homeSubtitle,
                createBottle: {
                    openBottleCreation()
                },
                openBottle: { bottle in
                    selected = bottle.url
                    activePage = nil
                }
            )
        }
    }

    var filteredBottles: [Bottle] {
        if bottleFilter.isEmpty {
            bottleVM.bottles
                .sorted()
        } else {
            bottleVM.bottles
                .filter { $0.settings.name.localizedCaseInsensitiveContains(bottleFilter) }
                .sorted()
        }
    }

    private var sidebarTitlebarInset: CGFloat {
        48
    }

    private var resolvedDisplayName: String {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "there" : trimmedName
    }

    private var accountLicense: BourbonLicenseRecord {
        resolvedAccountLicense ?? BourbonLicenseRecord(
            publicLicenseId: "BRBN-00000001",
            licenseToken: "",
            licenseKey: nil,
            installId: "",
            displayName: resolvedDisplayName == "there" ? "Bourbon User" : resolvedDisplayName,
            status: "Active",
            messages: ["Welcome to Bourbon."],
            permissions: ["Distillery: Enabled", "Uploads: Enabled"],
            warnings: [],
            strikes: 0
        )
    }
}

private struct BourbonWineRuntimeUpdateView: View {
    let availableVersion: SemanticVersion
    let close: () -> Void

    @State private var isUpdating = false
    @State private var status = "Ready to install the available runtime."
    @State private var failure: String?
    @State private var completed = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: completed ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(completed ? .green : .accentColor)
            Text("New Version of BourbonWine Available")
                .font(.title2.bold())
            Text(
                "BourbonWine \(installedVersion) is installed. " +
                    "BourbonWine \(availableVersion) is available."
            )
                .multilineTextAlignment(.center)
            if isUpdating {
                ProgressView()
                Text(status)
                    .foregroundStyle(.secondary)
            } else if let failure {
                Text(failure)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            } else {
                Text(completed ? "BourbonWine is installed and ready. You can create a Bottle now." : status)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack {
                Button(completed ? "Close" : "Cancel", action: close)
                    .disabled(isUpdating)
                Button("Update") {
                    update()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUpdating || completed)
            }
        }
        .padding(28)
        .frame(width: 480)
        .interactiveDismissDisabled(isUpdating)
    }

    private func update() {
        WhiskyWineInstaller.recordUpdateEvent("runtime.update.button.clicked")
        isUpdating = true
        failure = nil
        status = "Starting BourbonWine update…"
        Task {
            do {
                WhiskyWineInstaller.recordUpdateEvent("runtime.update.started", detail: "target=\(availableVersion)")
                status = "Verifying and installing BourbonWine \(availableVersion)…"
                let installedVersion = try await WhiskyWineInstaller.installLatestRuntimeUpdate()
                let runtimeReady = await Task.detached(priority: .userInitiated) {
                    WhiskyWineInstaller.runtimeReadiness(in: WhiskyWineInstaller.applicationFolder).isReady
                }.value
                guard installedVersion == String(availableVersion),
                      runtimeReady else {
                    throw NSError(
                        domain: "BourbonWineUpdate",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "The runtime install completed but BourbonWine readiness validation did not pass."
                        ]
                    )
                }
                completed = true
                status = "BourbonWine \(installedVersion) installed successfully."
            } catch {
                let safeError = error.localizedDescription.replacingOccurrences(of: "\n", with: " ")
                WhiskyWineInstaller.recordUpdateEvent(
                    "runtime.update.failed",
                    detail: "stage=update error=\(safeError)"
                )
                failure = "BourbonWine update failed: \(safeError)"
            }
            isUpdating = false
        }
    }

    private var installedVersion: String {
        WhiskyWineInstaller.whiskyWineVersion().map(String.init(describing:)) ?? "0.0.0"
    }
}

enum MainContentPage {
    case home
    case library
    case account
    case setup
    case createBottle
}

struct SidebarPageButton: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                    .frame(width: 20)

                Text(title)
                    .fontWeight(isActive ? .semibold : .regular)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? BourbonStyle.amber : .primary)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(BourbonStyle.amber.opacity(0.14))
            }
        }
    }
}

struct BourbonHomeView: View {
    let bottles: [Bottle]
    let displayName: String
    let subtitle: String
    let createBottle: () -> Void
    let openBottle: (Bottle) -> Void

    var body: some View {
        BourbonPage {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    HStack(alignment: .top, spacing: 22) {
                        VStack(alignment: .leading, spacing: 22) {
                            overviewCard
                            topBottlesCard
                        }
                        .frame(maxWidth: 620)

                        VStack(spacing: 22) {
                            donationsCard
                            messagesCard
                        }
                        .frame(width: 320)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(32)
                .frame(maxWidth: 1040)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Home")
        .onAppear {
            refreshInstalledApplicationCounts()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome, \(displayName)")
                .font(.largeTitle.bold())
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var overviewCard: some View {
        BourbonGlassCard(maxWidth: 620, cornerRadius: 22) {
            HStack(spacing: 18) {
                overviewMetric(
                    title: "Bottles",
                    value: "\(availableBottles.count)",
                    systemImage: "shippingbox"
                )

                divider

                overviewMetric(
                    title: "Installed apps",
                    value: "\(installedApplicationCount)",
                    systemImage: "app.badge"
                )

                Spacer(minLength: 12)

                Button {
                    createBottle()
                } label: {
                    Label("Create Bottle", systemImage: "plus")
                }
                .buttonStyle(BourbonPrimaryButtonStyle())
                .help("Create a new bottle for a Windows app or game.")
            }
        }
    }

    private var topBottlesCard: some View {
        BourbonGlassCard(maxWidth: 620, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Your Bottles")
                        .font(.title2.bold())
                    Spacer()
                    Text("Top 3")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                if topBottles.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("No bottles yet.")
                            .font(.headline)
                        Text("Create a bottle to install your first Windows app.")
                            .foregroundStyle(.secondary)
                        Button {
                            createBottle()
                        } label: {
                            Label("Create Bottle", systemImage: "plus")
                        }
                        .buttonStyle(BourbonSecondaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 12) {
                        ForEach(topBottles) { bottle in
                            Button {
                                openBottle(bottle)
                            } label: {
                                bottleRow(bottle)
                            }
                            .buttonStyle(.plain)
                            .help("Open \(bottle.settings.name).")
                        }
                    }
                }
            }
        }
    }

    private var donationsCard: some View {
        BourbonGlassCard(maxWidth: 320, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Top Donations", systemImage: "heart")
                    .font(.title3.bold())
                    .foregroundStyle(BourbonStyle.amber)

                Text("Coming soon")
                    .font(.headline)

                Text("Community support highlights will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var messagesCard: some View {
        BourbonGlassCard(maxWidth: 320, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Messages", systemImage: "text.bubble")
                    .font(.title3.bold())
                    .foregroundStyle(BourbonStyle.amber)

                Text("There are no new messages.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var availableBottles: [Bottle] {
        bottles.filter(\.isAvailable).sorted()
    }

    private var topBottles: [Bottle] {
        Array(availableBottles.prefix(3))
    }

    private var installedApplicationCount: Int {
        availableBottles.reduce(0) { total, bottle in
            total + bottle.programs.count
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.1))
            .frame(width: 1, height: 48)
    }

    private func overviewMetric(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(BourbonStyle.amber)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title.bold())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bottleRow(_ bottle: Bottle) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "shippingbox.fill")
                .font(.title3)
                .foregroundStyle(BourbonStyle.amber)
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(bottle.settings.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("\(bottle.programs.count) installed app\(bottle.programs.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }

    private func refreshInstalledApplicationCounts() {
        for bottle in availableBottles {
            bottle.updateInstalledPrograms()
        }
    }
}

struct GlobalInstallStatusBanner: View {
    @ObservedObject var manager: InstallManager

    var body: some View {
        if manager.isInstalling || manager.noticeMessage != nil || manager.lastError != nil {
            BourbonGlassCard(maxWidth: 420, cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        statusIcon

                        VStack(alignment: .leading, spacing: 2) {
                            Text(manager.noticeMessage ?? manager.progressStage.title)
                                .font(.headline)
                            Text(detailText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            manager.clearNotice()
                            manager.clearFinishedInstall()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .help("Dismiss this status.")
                    }

                    if let error = manager.lastError {
                        HStack {
                            Button("Try Again") {
                                manager.retryLastInstall()
                            }
                            .buttonStyle(BourbonPrimaryButtonStyle())

                            Button("Choose Another Installer") {
                                manager.chooseAnotherInstaller()
                            }
                            .buttonStyle(BourbonSecondaryButtonStyle())

                            Button("Report Issue") {
                                reportIssue(error)
                            }
                            .buttonStyle(BourbonSecondaryButtonStyle())
                        }
                    }
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var detailText: String {
        if let notice = manager.noticeMessage {
            return notice
        }

        let bottle = manager.activeBottleName ?? "Bottle"
        let installer = manager.installerName ?? "Installer"
        return "\(installer) in \(bottle). \(manager.progressDetail)"
    }

    @ViewBuilder
    private var statusIcon: some View {
        if manager.lastError != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BourbonStyle.amber)
        } else if manager.progressStage == .completed {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if manager.noticeMessage != nil {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(BourbonStyle.amber)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    private func reportIssue(_ error: InstallerErrorInfo) {
        BourbonReportCenter.openInstallerReport(
            bottleName: error.bottleName,
            installerURL: error.installerURL,
            errorMessage: error.message
        )
    }
}

#Preview {
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    ContentView(showSetup: .constant(false), updater: updaterController.updater)
        .environmentObject(BottleVM.shared)
}

enum BourbonStyle {
    static let amber = Color(red: 0.95, green: 0.63, blue: 0.24)
    static let amberDeep = Color(red: 0.58, green: 0.31, blue: 0.12)
    static let backgroundTop = Color(red: 0.12, green: 0.08, blue: 0.06)
    static let backgroundBottom = Color(red: 0.03, green: 0.025, blue: 0.022)
    static let cardStroke = Color.white.opacity(0.14)
}

struct BourbonBackground<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [BourbonStyle.backgroundTop, BourbonStyle.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            content
        }
        .foregroundStyle(.white)
    }
}

struct BourbonPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [BourbonStyle.backgroundTop, BourbonStyle.backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .foregroundStyle(.white)
    }
}

struct BourbonPanelBackdrop<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.05),
                    Color.black.opacity(0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            content
                .padding(34)
        }
        .foregroundStyle(.white)
    }
}

struct BourbonFloatingPanel<Content: View>: View {
    var maxWidth: CGFloat = 560
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(30)
            .frame(maxWidth: maxWidth)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(.white.opacity(0.16))
                            }
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.34), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.82), radius: 54, y: 38)
            .shadow(color: .white.opacity(0.1), radius: 18, y: -10)
    }
}

struct BourbonGlassCard<Content: View>: View {
    var maxWidth: CGFloat = 560
    var cornerRadius: CGFloat = 24
    @ViewBuilder let content: Content

    var body: some View {
        let effectiveCornerRadius = min(cornerRadius, 8)

        content
            .padding(28)
            .frame(maxWidth: maxWidth)
            .background(
                .white.opacity(0.07),
                in: RoundedRectangle(cornerRadius: effectiveCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: effectiveCornerRadius, style: .continuous)
                    .stroke(BourbonStyle.cardStroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    }
}

struct BourbonPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [BourbonStyle.amber, Color(red: 0.78, green: 0.42, blue: 0.17)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .foregroundStyle(.black.opacity(0.82))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct BourbonSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                .white.opacity(configuration.isPressed ? 0.12 : 0.08),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .foregroundStyle(.white)
    }
}

struct DistilleryView: View {
    @State private var showRequestForm = false
    @State private var requestSubmitted = false

    var body: some View {
        Group {
            if showRequestForm {
                DistilleryRequestView(
                    requestSubmitted: $requestSubmitted,
                    cancel: {
                        showRequestForm = false
                    }
                )
            } else {
                BourbonPage {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Distillery")
                            .font(.largeTitle.bold())
                            .padding(.horizontal, 32)
                            .padding(.top, 32)

                        GeometryReader { proxy in
                            ScrollView {
                                comingSoonCard
                                    .padding(.horizontal, 32)
                                    .padding(.bottom, 32)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: proxy.size.height, alignment: .center)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Distillery")
    }

    private var comingSoonCard: some View {
        BourbonGlassCard(maxWidth: 900, cornerRadius: 16) {
            VStack(spacing: 18) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(BourbonStyle.amber)
                    .frame(width: 72, height: 72)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                Text("Coming soon!")
                    .font(.largeTitle.bold())

                Text("A curated collection of games and apps ready to install at your fingertips.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    showRequestForm = true
                } label: {
                    Label("Request a Game or App", systemImage: "plus.bubble")
                        .font(.headline)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                }
                .buttonStyle(BourbonPrimaryButtonStyle())
                .controlSize(.large)
                .help("Request a game or app for the Distillery.")

                if requestSubmitted {
                    Text("Request submitted for review.")
                        .font(.caption)
                        .foregroundStyle(BourbonStyle.amber)
                }
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.vertical, 6)
        }
    }
}

struct LibrarySubmission: Identifiable, Codable {
    let id: UUID
    var appName: String
    var officialWebsite: String
    var officialDownloadURL: String
    var category: String
    var notes: String
    var status: LibrarySubmissionStatus
    var submittedAt: Date

    init(
        id: UUID = UUID(),
        appName: String,
        officialWebsite: String,
        officialDownloadURL: String,
        category: String,
        notes: String,
        status: LibrarySubmissionStatus = .pending,
        submittedAt: Date = Date()
    ) {
        self.id = id
        self.appName = appName
        self.officialWebsite = officialWebsite
        self.officialDownloadURL = officialDownloadURL
        self.category = category
        self.notes = notes
        self.status = status
        self.submittedAt = submittedAt
    }
}

enum LibrarySubmissionStatus: String, Codable {
    case pending
    case approved
    case rejected
    case needsChanges
}

struct LibraryItem: Identifiable, Codable {
    let id: UUID
    var name: String
    var publisher: String
    var category: String
    var officialWebsite: String
    var officialDownloadURL: String
    var status: LibraryItemStatus
    var iconURL: URL?
    var logoAssetName: String?
}

enum LibraryItemStatus: String, Codable {
    case published
    case hidden
    case removed
}

struct DistilleryRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var requestSubmitted: Bool
    var cancel: () -> Void = {}
    @State private var appName = ""
    @State private var officialWebsite = ""
    @State private var officialDownloadURL = ""
    @State private var category = "Games"
    @State private var notes = ""
    @State private var confirmsAuthorizedSoftware = false

    private let categories = ["Games", "Launchers", "Utilities", "Productivity", "Development", "Media", "Browsers"]

    var body: some View {
        BourbonPanelBackdrop {
            ScrollView {
                BourbonFloatingPanel(maxWidth: 680) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Request a Game or App")
                            .font(.largeTitle.bold())
                        Text(
                            "Requests are reviewed before appearing in the Bourbon Distillery. " +
                            "No binaries are uploaded."
                        )
                            .foregroundStyle(.secondary)

                        TextField("Game or app name", text: $appName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Official website", text: $officialWebsite)
                            .textFieldStyle(.roundedBorder)
                        TextField("Official download URL", text: $officialDownloadURL)
                            .textFieldStyle(.roundedBorder)
                        Picker("Category", selection: $category) {
                            ForEach(categories, id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }
                        TextField("Notes", text: $notes, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3, reservesSpace: true)

                        Toggle(
                            "I confirm this request does not include pirated, cracked, or unauthorized software.",
                            isOn: $confirmsAuthorizedSoftware
                        )
                        .toggleStyle(.checkbox)

                        HStack {
                            Button("Cancel") {
                                cancel()
                                dismiss()
                            }
                            .buttonStyle(BourbonSecondaryButtonStyle())

                            Spacer()

                            Button("Submit Request") {
                                requestSubmitted = true
                                let submission = LibrarySubmission(
                                    appName: appName,
                                    officialWebsite: officialWebsite,
                                    officialDownloadURL: officialDownloadURL,
                                    category: category,
                                    notes: notes
                                )
                                // Future endpoint: POST /library/submissions.
                                // Approved server-side items should publish into Distillery data
                                // without requiring an app update.
                                print("Distillery request submitted: \(submission)")
                                cancel()
                                dismiss()
                            }
                            .buttonStyle(BourbonPrimaryButtonStyle())
                            .disabled(!canSubmit)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .navigationTitle("Request")
    }

    private var canSubmit: Bool {
        !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !officialWebsite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !officialDownloadURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        confirmsAuthorizedSoftware
    }
}

enum BourbonHomeCopy {
    private static let subtitles = [
        "Have fun brewing.",
        "Your bottle is ready.",
        "Let’s get something running.",
        "Fresh pour, fresh start.",
        "Ready to install something?"
    ]

    static func randomSubtitle() -> String {
        subtitles.randomElement() ?? "Ready to install something?"
    }
}

struct AccountPageView: View {
    let displayName: String
    let license: BourbonLicenseRecord
    @State private var showingStandingDetails = false
    @State private var copiedLicense = false
    @AppStorage(BourbonUpdatePolicy.preReleaseUpdatesEnabledKey) private var preReleaseUpdatesEnabled = false

    var body: some View {
        BourbonPage {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    accountStatusCard
                    BourbonBuildDiagnosticsCard()

                    if showingStandingDetails {
                        standingDetailsCard
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(32)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("Account")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome, \(resolvedDisplayName)")
                .font(.largeTitle.bold())
            Text("Here’s your account standing.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var accountStatusCard: some View {
        BourbonGlassCard(maxWidth: 900, cornerRadius: 20) {
            VStack(spacing: 0) {
                accountStandingRow
                divider
                licenseRow
                divider
                accountRow(title: "Bourbon Board Member", value: "Coming soon")
                divider
                preReleaseRow
            }
        }
    }

    private var standingDetailsCard: some View {
        BourbonGlassCard(maxWidth: 900, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 18) {
                Label("Account Standing Details", systemImage: "info.circle")
                    .font(.headline)
                    .foregroundStyle(BourbonStyle.amber)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    detailTile(title: "Warnings", value: "\(license.warnings.count)")
                    detailTile(title: "Strikes", value: "\(license.strikes)")
                    detailTile(title: "Current Permissions", value: formattedPermissions)
                    detailTile(title: "Account Messages", value: formattedMessages)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Standing levels")
                        .font(.headline)
                    standingDefinition("Good", "No active issues.", color: .green)
                    standingDefinition("Degraded", "Warnings or limited permissions.", color: BourbonStyle.amber)
                    standingDefinition("Bad", "Suspended or banned status.", color: .red)
                }
            }
        }
    }

    private var accountStandingRow: some View {
        Button {
            withAnimation(.snappy) {
                showingStandingDetails.toggle()
            }
        } label: {
            accountRowContent(
                title: "Account Standing",
                value: accountStanding.title,
                valueColor: accountStanding.color,
                accessory: Image(systemName: showingStandingDetails ? "chevron.up" : "chevron.down")
            )
        }
        .buttonStyle(.plain)
        .help("Explain what your account standing means.")
    }

    private var licenseRow: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(license.publicLicenseId, forType: .string)
            withAnimation(.snappy) {
                copiedLicense = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.snappy) {
                    copiedLicense = false
                }
            }
        } label: {
            accountRowContent(
                title: "License ID",
                value: copiedLicense ? "Copied" : license.publicLicenseId,
                valueColor: copiedLicense ? .green : .primary,
                accessory: Image(systemName: copiedLicense ? "checkmark.circle.fill" : "doc.on.doc")
            )
        }
        .buttonStyle(.plain)
        .help("Copy your public license ID.")
    }

    private var preReleaseRow: some View {
        accountRow(
            title: "Pre-release Sign Up",
            value: preReleaseUpdatesEnabled ? "Yes" : "No",
            valueColor: preReleaseUpdatesEnabled ? BourbonStyle.amber : .green
        )
        .help("Pre-release sign up controls will be added here later.")
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(height: 1)
    }

    private var resolvedDisplayName: String {
        displayName == "there" ? "Bourbon User" : displayName
    }

    private var accountStanding: (title: String, color: Color) {
        let normalizedStatus = license.status.lowercased()
        if normalizedStatus.contains("suspended") ||
            normalizedStatus.contains("banned") ||
            normalizedStatus.contains("bad") ||
            license.strikes >= 3 {
            return ("Bad", .red)
        }

        if normalizedStatus.contains("limited") ||
            normalizedStatus.contains("degraded") ||
            !license.warnings.isEmpty ||
            license.strikes > 0 {
            return ("Degraded", BourbonStyle.amber)
        }

        return ("Good", .green)
    }

    private var formattedPermissions: String {
        let permissions = license.permissions.isEmpty ? ["distillery", "uploads"] : license.permissions
        return permissions
            .map { permission in
                switch permission.lowercased() {
                case "library", "library: enabled", "distillery", "distillery: enabled":
                    return "Distillery access"
                case "uploads", "uploads: enabled":
                    return "Uploads"
                case "local-installs":
                    return "Local installs"
                default:
                    return permission
                        .replacingOccurrences(of: "-", with: " ")
                        .replacingOccurrences(of: ": enabled", with: "", options: .caseInsensitive)
                        .capitalized
                }
            }
            .joined(separator: ", ")
    }

    private var formattedMessages: String {
        let visibleMessages = license.messages.filter { message in
            let normalizedMessage = message.lowercased()
            return !normalizedMessage.contains("local mock account")
        }
        return visibleMessages.isEmpty ? "No account messages." : visibleMessages.joined(separator: "\n")
    }

    private func accountRow(title: String, value: String, valueColor: Color = .primary) -> some View {
        accountRowContent(title: title, value: value, valueColor: valueColor, accessory: nil)
    }

    private func accountRowContent(
        title: String,
        value: String,
        valueColor: Color,
        accessory: Image?
    ) -> some View {
        HStack(spacing: 18) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Spacer(minLength: 24)
            HStack(spacing: 8) {
                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(valueColor)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                accessory
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    private func detailTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func standingDefinition(_ title: String, _ description: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .fontWeight(.semibold)
            Text(description)
                .foregroundStyle(.secondary)
        }
    }
}

struct BourbonBuildInfo: Decodable {
    let gitCommit: String?
    let gitBranch: String?
    let gitRef: String?
    let gitTag: String?
    let marketingVersion: String?
    let buildNumber: String?
    let buildDateUTC: String?
}

struct BourbonBuildDiagnosticsCard: View {
    private let diagnostics = BourbonBuildDiagnostics.current

    var body: some View {
        BourbonGlassCard(maxWidth: 900, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 16) {
                Label("About \(diagnostics.displayName)", systemImage: "info.circle")
                    .font(.headline)
                    .foregroundStyle(BourbonStyle.amber)

                VStack(spacing: 0) {
                    diagnosticRow(title: "Version", value: diagnostics.version)
                    divider
                    diagnosticRow(title: "Build number", value: diagnostics.buildNumber)
                    divider
                    diagnosticRow(title: "Git commit", value: diagnostics.gitCommitShort)
                    divider
                    diagnosticRow(title: "Build date", value: diagnostics.buildDateUTC)
                    divider
                    diagnosticRow(title: "Update feed", value: diagnostics.updateFeedURL)
                }
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(height: 1)
    }

    private func diagnosticRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 24)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 12)
    }
}

struct BourbonBuildDiagnostics {
    let displayName: String
    let version: String
    let buildNumber: String
    let gitCommit: String
    let gitCommitShort: String
    let buildDateUTC: String
    let updateFeedURL: String

    static let current: BourbonBuildDiagnostics = {
        let infoDictionary = Bundle.main.infoDictionary ?? [:]
        let buildInfo = loadBuildInfo()
        let version = buildInfo?.marketingVersion ??
        infoDictionary["CFBundleShortVersionString"] as? String ??
        "Unknown"
        let buildNumber = buildInfo?.buildNumber ??
        infoDictionary["CFBundleVersion"] as? String ??
        "Unknown"
        let commit = buildInfo?.gitCommit ?? "Local build"
        let shortCommit = commit == "Local build" ? commit : String(commit.prefix(12))
        let buildDate = buildInfo?.buildDateUTC ?? "Unavailable"
        let feedURL = infoDictionary["SUFeedURL"] as? String ?? "Unavailable"

        return BourbonBuildDiagnostics(
            displayName: infoDictionary["CFBundleDisplayName"] as? String ?? "Bourbon",
            version: version,
            buildNumber: buildNumber,
            gitCommit: commit,
            gitCommitShort: shortCommit,
            buildDateUTC: buildDate,
            updateFeedURL: feedURL
        )
    }()

    private static func loadBuildInfo() -> BourbonBuildInfo? {
        guard let url = Bundle.main.url(forResource: "BuildInfo", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(BourbonBuildInfo.self, from: data)
    }
}

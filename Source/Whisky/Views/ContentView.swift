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
import UniformTypeIdentifiers
import WhiskyKit
import SemanticVersion

// swiftlint:disable file_length

// swiftlint:disable:next type_body_length
struct ContentView: View {
    @AppStorage("selectedBottleURL") private var selectedBottleURL: URL?
    @AppStorage("hasCompletedFirstRunOnboarding") private var hasCompletedFirstRunOnboarding = false
    @AppStorage("hasDismissedLegacyWineWarning") private var hasDismissedLegacyWineWarning = false
    @AppStorage("displayName") private var displayName = ""
    @EnvironmentObject var bottleVM: BottleVM
    @ObservedObject private var installManager = InstallManager.shared
    @Binding var showSetup: Bool

    @State private var selected: URL?
    @State private var showBottleCreation: Bool = false
    @State private var bottlesLoaded: Bool = false
    @State private var showBottleSelection: Bool = false
    @State private var newlyCreatedBottleURL: URL?
    @State private var firstInstallBottleURL: URL?
    @State private var firstInstallerURL: URL?
    @State private var showingMarketplace = false
    @State private var showAccountPanel = false
    @State private var openedFileURL: URL?
    @State private var triggerRefresh: Bool = false
    @State private var refreshAnimation: Angle = .degrees(0)
    @State private var homeSubtitle = BourbonHomeCopy.randomSubtitle()

    @State private var bottleFilter = ""

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .overlay(alignment: .bottomTrailing) {
            GlobalInstallStatusBanner(manager: installManager)
                .padding()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAccountPanel = true
                } label: {
                    Label("Account", systemImage: "person.crop.circle")
                }
                .help("View your Bourbon account.")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showBottleCreation.toggle()
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
        .sheet(isPresented: $showBottleCreation) {
            BottleCreationView(
                newlyCreatedBottleURL: $newlyCreatedBottleURL,
                selectedInstallerURL: $firstInstallerURL
            )
        }
        .sheet(isPresented: Binding(
            get: { firstInstallBottleURL != nil },
            set: { isPresented in
                if !isPresented {
                    firstInstallBottleURL = nil
                }
            }
        )) {
            if let firstInstallBottleURL,
               let bottle = bottleVM.bottles.first(where: { $0.url == firstInstallBottleURL }) {
                FirstInstallView(bottle: bottle, initialInstallerURL: firstInstallerURL) {
                    self.firstInstallerURL = nil
                    self.firstInstallBottleURL = nil
                }
            }
        }
        .sheet(isPresented: $showSetup) {
            SetupView(
                showSetup: $showSetup,
                showBottleCreation: $showBottleCreation,
                firstTime: !hasCompletedFirstRunOnboarding
            )
        }
        .sheet(item: $openedFileURL) { url in
            FileOpenView(fileURL: url,
                         currentBottle: selected,
                         bottles: bottleVM.bottles)
        }
        .sheet(isPresented: $showAccountPanel) {
            AccountPanelSheet(displayName: resolvedDisplayName, license: accountLicense)
        }
        .onChange(of: selected) {
            selectedBottleURL = selected
        }
        .handlesExternalEvents(preferring: [], allowing: ["*"])
        .onOpenURL { url in
            openedFileURL = url
        }
        .task {
            bottleVM.loadBottles()
            bottlesLoaded = true

            if !bottleVM.bottles.isEmpty || bottleVM.countActive() != 0 {
                if let bottle = bottleVM.bottles.first(where: { $0.url == selectedBottleURL && $0.isAvailable }) {
                    selected = bottle.url
                } else {
                    selected = bottleVM.bottles[0].url
                }
            }

            if !WhiskyWineInstaller.isWhiskyWineInstalled() {
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
            if updateInfo.0 {
                let alert = NSAlert()
                alert.messageText = String(localized: "update.bourbonwine.title")
                alert.informativeText = String(
                    format: "BourbonWine %@ is installed. BourbonWine %@ is available.",
                    String(WhiskyWineInstaller.whiskyWineVersion() ?? SemanticVersion(0, 0, 0)),
                    String(updateInfo.1)
                )
                alert.alertStyle = .warning
                alert.addButton(withTitle: String(localized: "update.bourbonwine.update"))
                alert.addButton(withTitle: String(localized: "button.removeAlert.cancel"))

                let response = alert.runModal()

                if response == .alertFirstButtonReturn {
                    WhiskyWineInstaller.uninstall()
                    showSetup = true
                }
            }
        }
    }

    private func showLegacyRuntimeWarning(markerURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Older Wine Runner Detected"
        alert.informativeText = """
        Bourbon found an older WhiskyWine runtime marker at:
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
        ScrollViewReader { proxy in
            List(selection: $selected) {
                Section {
                    Button {
                        selected = nil
                        showingMarketplace = true
                    } label: {
                        Label("Library", systemImage: "books.vertical")
                    }
                    .buttonStyle(.plain)
                    .help("Browse games and apps.")
                }

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
            .searchable(text: $bottleFilter, placement: .sidebar)
            .onChange(of: selected) {
                showingMarketplace = false
            }
            .onChange(of: newlyCreatedBottleURL) { _, url in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    selected = url
                    firstInstallBottleURL = url
                    if url != nil {
                        hasCompletedFirstRunOnboarding = true
                    }
                    withAnimation {
                        proxy.scrollTo(url, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    var detail: some View {
        if showingMarketplace {
            MarketplaceView()
        } else if let bottle = selected {
            if let bottle = bottleVM.bottles.first(where: { $0.url == bottle }) {
                BottleView(bottle: bottle)
                    .disabled(bottle.inFlight)
                    .id(bottle.url)
            }
        } else {
            if (bottleVM.bottles.isEmpty || bottleVM.countActive() == 0) && bottlesLoaded {
                BourbonBackground {
                    VStack(spacing: 16) {
                        BourbonGlassCard(maxWidth: 420) {
                            VStack(spacing: 16) {
                                Image(systemName: "shippingbox.fill")
                                    .font(.system(size: 42, weight: .semibold))
                                    .foregroundStyle(BourbonStyle.amber)

                                Text(homeTitle)
                                    .font(.title2.bold())

                                Text(homeSubtitle)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)

                                Button {
                                    showBottleCreation.toggle()
                                } label: {
                                    Label("Create Bottle", systemImage: "plus")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(BourbonPrimaryButtonStyle())
                                .help("Create a new bottle for a Windows app or game.")
                            }
                        }

                        if let license = LicenseKeychainStore.currentLicense() {
                            AccountPanelView(displayName: resolvedDisplayName, license: license)
                        }
                    }
                }
            }
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

    private var resolvedDisplayName: String {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "there" : trimmedName
    }

    private var homeTitle: String {
        "Welcome, \(resolvedDisplayName)"
    }

    private var accountLicense: BourbonLicenseRecord {
        LicenseKeychainStore.currentLicense() ?? BourbonLicenseRecord(
            publicLicenseId: "BRBN-00000001",
            licenseToken: "",
            installId: "",
            displayName: resolvedDisplayName == "there" ? "Bourbon User" : resolvedDisplayName,
            status: "Active",
            messages: ["Welcome to Bourbon."],
            permissions: ["Library: Enabled", "Uploads: Enabled"],
            warnings: [],
            strikes: 0
        )
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
        let payload = InstallerIssueReporter.reportPayload(
            bottleName: error.bottleName,
            installerURL: error.installerURL,
            errorMessage: error.message
        )
        print(payload)

        guard InstallerIssueReporter.confirmBeforeOpeningReport() else { return }

        if let url = URL(string: "https://github.com/Bourbon-App/Bourbon/issues/new") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    ContentView(showSetup: .constant(false))
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

struct BourbonGlassCard<Content: View>: View {
    var maxWidth: CGFloat = 560
    var cornerRadius: CGFloat = 24
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(28)
            .frame(maxWidth: maxWidth)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(BourbonStyle.cardStroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 28, y: 18)
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

struct MarketplaceView: View {
    @State private var searchText = ""
    @State private var selectedCategory = "Games"
    @State private var showRequestForm = false
    @State private var requestSubmitted = false

    private let categories = [
        "Games",
        "Launchers",
        "Utilities",
        "Productivity",
        "Development",
        "Media",
        "Browsers",
        "Modding",
        "Community"
    ]

    private let featuredApps = [
        MarketplaceApp(
            name: "Steam",
            publisher: "Valve",
            category: "Launchers",
            compatibility: "Good",
            sourceType: "Official installer",
            description: "Install Valve’s game launcher from the official Steam download page.",
            officialWebsite: "https://store.steampowered.com/about/"
        ),
        MarketplaceApp(name: "Epic Games Launcher",
                       publisher: "Epic Games",
                       category: "Launchers",
                       compatibility: "Testing",
                       sourceType: "Official installer",
                       description: "Epic’s launcher using official download links only.",
                       officialWebsite: "https://store.epicgames.com/download"),
        MarketplaceApp(name: "Battle.net",
                       publisher: "Blizzard Entertainment",
                       category: "Launchers",
                       compatibility: "Testing",
                       sourceType: "Official installer",
                       description: "Install Blizzard’s launcher from the official Battle.net download page.",
                       officialWebsite: "https://www.blizzard.com/apps/battle.net/desktop"),
        MarketplaceApp(name: "Roblox",
                       publisher: "Roblox Corporation",
                       category: "Games",
                       compatibility: "Community testing",
                       sourceType: "Official installer",
                       description: "Community-requested placeholder for Roblox’s official Windows installer.",
                       officialWebsite: "https://www.roblox.com/download"),
        MarketplaceApp(name: "GOG Galaxy",
                       publisher: "GOG",
                       category: "Launchers",
                       compatibility: "Testing",
                       sourceType: "Official installer",
                       description: "Install GOG’s official library client with Bourbon compatibility notes.",
                       officialWebsite: "https://www.gog.com/galaxy"),
        MarketplaceApp(name: "Discord",
                       publisher: "Discord Inc.",
            category: "Community",
                       compatibility: "Good",
                       sourceType: "Official installer",
                       description: "Electron app support with safe rendering fallback flags when needed.",
                       officialWebsite: "https://discord.com/download"),
        MarketplaceApp(name: "OBS Studio",
                       publisher: "OBS Project",
                       category: "Media",
                       compatibility: "Testing",
                       sourceType: "Official installer",
                       description: "Open-source broadcaster linked from the official OBS site.",
                       officialWebsite: "https://obsproject.com/download"),
        MarketplaceApp(name: "Notepad++",
                       publisher: "Notepad++ Team",
                       category: "Utilities",
                       compatibility: "Good",
                       sourceType: "Official installer",
                       description: "Lightweight editor using official Notepad++ release links.",
                       officialWebsite: "https://notepad-plus-plus.org/downloads/"),
        MarketplaceApp(name: "WinRAR",
                       publisher: "win.rar GmbH",
                       category: "Utilities",
                       compatibility: "Good",
                       sourceType: "Official installer",
                       description: "Archive manager from WinRAR’s official download page.",
                       officialWebsite: "https://www.win-rar.com/download.html"),
        MarketplaceApp(name: "7-Zip",
                       publisher: "Igor Pavlov",
                       category: "Utilities",
                       compatibility: "Great",
                       sourceType: "Official installer",
                       description: "Archive utility using official 7-Zip download links.",
                       officialWebsite: "https://www.7-zip.org/download.html")
    ]

    var body: some View {
        BourbonBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    categoryPicker
                    appGrid
                    submissionCard
                }
                .padding(32)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .navigationTitle("Library")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search applications")
        .sheet(isPresented: $showRequestForm) {
            LibraryRequestView(requestSubmitted: $requestSubmitted)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Coming soon!")
                .font(.largeTitle.bold())
            Text("A library of games and apps ready to install at your fingertips.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button {
                showRequestForm = true
            } label: {
                Label("Request a Game or App", systemImage: "plus.bubble")
            }
            .buttonStyle(BourbonPrimaryButtonStyle())
            .help("Request a game or app for the Library.")

            if requestSubmitted {
                Text("Request submitted for review.")
                    .font(.caption)
                    .foregroundStyle(BourbonStyle.amber)
            }
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    if category == selectedCategory {
                        Button(category) {
                            selectedCategory = category
                        }
                        .buttonStyle(BourbonPrimaryButtonStyle())
                        .help("Show \(category.lowercased()) entries.")
                    } else {
                        Button(category) {
                            selectedCategory = category
                        }
                        .buttonStyle(BourbonSecondaryButtonStyle())
                        .help("Show \(category.lowercased()) entries.")
                    }
                }
            }
        }
    }

    private var appGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
            ForEach(filteredApps) { app in
                MarketplaceAppCard(app: app)
            }
        }
    }

    private var submissionCard: some View {
        BourbonGlassCard(maxWidth: 980, cornerRadius: 18) {
            HStack(spacing: 18) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(BourbonStyle.amber)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Request an app or game")
                        .font(.headline)
                    Text("Tell us what you want to see next. Requests are reviewed before appearing in Library.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Request a Game or App") {
                    showRequestForm = true
                }
                .buttonStyle(BourbonSecondaryButtonStyle())
                .help("Request a Library entry for review.")
            }
        }
    }

    private var filteredApps: [MarketplaceApp] {
        featuredApps.filter { app in
            let matchesCategory = app.category == selectedCategory || selectedCategory == "Community"
            let matchesSearch = searchText.isEmpty ||
            app.name.localizedCaseInsensitiveContains(searchText) ||
            app.publisher.localizedCaseInsensitiveContains(searchText) ||
            app.category.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }
}

struct MarketplaceApp: Identifiable {
    let id = UUID()
    let name: String
    let publisher: String
    let category: String
    let compatibility: String
    let sourceType: String
    let description: String
    let officialWebsite: String
    let iconURL: URL?
    let logoAssetName: String?

    init(
        name: String,
        publisher: String,
        category: String,
        compatibility: String,
        sourceType: String,
        description: String,
        officialWebsite: String,
        iconURL: URL? = nil,
        logoAssetName: String? = nil
    ) {
        self.name = name
        self.publisher = publisher
        self.category = category
        self.compatibility = compatibility
        self.sourceType = sourceType
        self.description = description
        self.officialWebsite = officialWebsite
        self.iconURL = iconURL
        self.logoAssetName = logoAssetName
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

struct MarketplaceAppCard: View {
    let app: MarketplaceApp

    var body: some View {
        BourbonGlassCard(maxWidth: 320, cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    appLogo
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name)
                            .font(.headline)
                        Text(app.publisher)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(app.compatibility)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.08), in: Capsule())
                        .foregroundStyle(BourbonStyle.amber)
                }

                Text(app.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Label(app.category, systemImage: "folder")
                    Text(app.sourceType)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(BourbonStyle.amber.opacity(0.18), in: Capsule())
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    Button {
                        print("TODO: Library install selected for \(app.name): \(app.officialWebsite)")
                    } label: {
                        Label("Install", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BourbonPrimaryButtonStyle())
                    .help("Install \(app.name) from official links.")

                    Button("Details") {
                        if let url = URL(string: app.officialWebsite) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(BourbonSecondaryButtonStyle())
                    .help("Open official website details.")
                }
            }
        }
    }

    @ViewBuilder
    private var appLogo: some View {
        if let logoAssetName = app.logoAssetName,
           NSImage(named: logoAssetName) != nil {
            Image(logoAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if let iconURL = app.iconURL {
            AsyncImage(url: iconURL) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                placeholderLogo
            }
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            placeholderLogo
        }
    }

    private var placeholderLogo: some View {
        Image(systemName: "app.badge")
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(BourbonStyle.amber)
            .frame(width: 42, height: 42)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct LibraryRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var requestSubmitted: Bool
    @State private var appName = ""
    @State private var officialWebsite = ""
    @State private var officialDownloadURL = ""
    @State private var category = "Games"
    @State private var notes = ""
    @State private var confirmsAuthorizedSoftware = false

    private let categories = ["Games", "Launchers", "Utilities", "Productivity", "Development", "Media", "Browsers"]

    var body: some View {
        BourbonBackground {
            BourbonGlassCard(maxWidth: 560) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Request a Game or App")
                        .font(.largeTitle.bold())
                    Text("Requests are reviewed before appearing in Bourbon Library. No binaries are uploaded.")
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
                            // Approved server-side items should publish into Library data
                            // without requiring an app update.
                            print("Library request submitted: \(submission)")
                            dismiss()
                        }
                        .buttonStyle(BourbonPrimaryButtonStyle())
                        .disabled(!canSubmit)
                    }
                }
            }
        }
        .frame(width: 680, height: 620)
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

struct AccountPanelView: View {
    let displayName: String
    let license: BourbonLicenseRecord
    var updateAvailable = false

    var body: some View {
        BourbonGlassCard(maxWidth: 420, cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Account", systemImage: "person.crop.circle")
                    .font(.headline)
                    .foregroundStyle(BourbonStyle.amber)

                accountRow("Display name", displayName)
                accountRow("Public license ID", license.publicLicenseId)
                accountRow("License status", license.status)
                accountRow("Warnings", "\(license.warnings.count)")
                accountRow("Strikes", "\(license.strikes)")
                accountRow("Messages", license.messages.isEmpty ? "None" : license.messages.joined(separator: ", "))
                accountRow("App update status", appUpdateStatus)
                accountRow("Library permissions", libraryPermissions)

                if updateAvailable {
                    Button("Update Bourbon") {
                        if let url = URL(string: "https://getbourbon.app/") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(BourbonPrimaryButtonStyle())
                    .help("Download the latest Bourbon update.")
                }
            }
        }
    }

    private var appUpdateStatus: String {
        updateAvailable ? "Update available" : "Up to date"
    }

    private var libraryPermissions: String {
        if license.permissions.isEmpty {
            return "Library: Enabled, Uploads: Enabled"
        }
        return license.permissions.joined(separator: ", ")
    }

    private func accountRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.caption)
    }
}

struct AccountPanelSheet: View {
    @Environment(\.dismiss) private var dismiss
    let displayName: String
    let license: BourbonLicenseRecord

    var body: some View {
        BourbonBackground {
            VStack(spacing: 16) {
                AccountPanelView(displayName: resolvedDisplayName, license: license)

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(BourbonSecondaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 520, height: 520)
    }

    private var resolvedDisplayName: String {
        displayName == "there" ? "Bourbon User" : displayName
    }
}

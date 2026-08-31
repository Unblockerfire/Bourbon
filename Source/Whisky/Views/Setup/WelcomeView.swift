//  WelcomeView.swift
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

import AppKit
import OSLog
import Security
import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit

// swiftlint:disable file_length

enum BourbonLicenseDiagnostics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? BourbonLicenseStoragePolicy.productionBundleIdentifier,
        category: "LicenseLifecycle"
    )

    static func record(_ event: String, detail: String? = nil) {
        let message = detail.map { "\(event) \($0)" } ?? event
        logger.notice("\(message, privacy: .public)")
        print(message)
    }
}

// swiftlint:disable:next type_body_length
struct WelcomeView: View {
    private enum OnboardingStep {
        case welcome
        case dependencies
        case displayName
        case legal
        case license
        case welcomeHome
    }

    @State var rosettaInstalled: Bool?
    @State var whiskyWineInstalled: Bool?
    @State var shouldCheckInstallStatus: Bool = false
    @State private var showManualSetup = false
    @State private var showBottleExplanation = false
    @State private var draftDisplayName = ""
    @State private var acceptedTerms = false
    @State private var accountError: String?
    @State private var isCreatingAccount = false
    @State private var activatedLicenseKey: String?
    @State private var hasUsableLicense = false
    @State private var installStatusRequestID = UUID()
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool
    @Binding var showBottleCreation: Bool
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @AppStorage("hasCompletedFirstRunOnboarding") private var hasCompletedFirstRunOnboarding = false
    @AppStorage("hasInstalledDependencies") private var hasInstalledDependencies = false
    @AppStorage("hasChosenDisplayName") private var hasChosenDisplayName = false
    @AppStorage("hasAcceptedLegalDocuments") private var hasAcceptedLegalDocuments = false
    @AppStorage("hasCreatedLicense") private var hasCreatedLicense = false
    @AppStorage("hasAcceptedLegalTerms") private var legacyAcceptedLegalTerms = false
    @AppStorage("hasCreatedFreeLicense") private var legacyCreatedFreeLicense = false
    @AppStorage("displayName") private var storedDisplayName = ""
    var firstTime: Bool

    var body: some View {
        BourbonPanelBackdrop {
            ScrollView {
                BourbonFloatingPanel(maxWidth: 560) {
                    Group {
                        switch currentStep {
                        case .welcome:
                            firstWelcomeContent
                        case .dependencies:
                            setupCheckContent
                        case .displayName:
                            displayNameContent
                        case .legal:
                            legalAcceptanceContent
                        case .license:
                            licenseCreationContent
                        case .welcomeHome:
                            welcomeContent
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 500)
                }
                .frame(maxWidth: .infinity, minHeight: 620)
            }
        }
        .navigationTitle("Welcome")
        .onAppear {
            migrateLegacyOnboardingFlags()
            checkInstallStatus()
        }
        .task {
            await refreshLicenseState()
        }
        .onChange(of: shouldCheckInstallStatus) {
            checkInstallStatus()
        }
    }

    private var firstWelcomeContent: some View {
        VStack(spacing: 18) {
            Image(systemName: "wineglass.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(BourbonStyle.amber)

            VStack(spacing: 6) {
                Text("Welcome to Bourbon")
                    .font(.largeTitle.bold())
                Text("Run your favorite Windows applications on macOS.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Get Started") {
                hasSeenWelcome = true
            }
            .buttonStyle(BourbonPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
    }

    private var setupCheckContent: some View {
        VStack(alignment: .center, spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(BourbonStyle.amber)

            VStack(spacing: 6) {
                Text("Setup check")
                    .font(.largeTitle.bold())
                Text("Bourbon needs a few pieces in place before it can open Windows apps.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                InstallStatusView(isInstalled: $rosettaInstalled,
                                  shouldCheckInstallStatus: $shouldCheckInstallStatus,
                                  name: "Rosetta")
                InstallStatusView(isInstalled: $whiskyWineInstalled,
                                  shouldCheckInstallStatus: $shouldCheckInstallStatus,
                                  showUninstall: true,
                                  name: "BourbonWine")
                SetupStatusRow(
                    title: "Runtime ready",
                    subtitle: "Bourbon is ready to create bottles and launch installers.",
                    isInstalled: runtimeReady
                )
            }
            .padding(.vertical, 4)

            if showManualSetup {
                ManualSetupView(rosettaInstalled: rosettaInstalled, whiskyWineInstalled: whiskyWineInstalled)
            }

            HStack {
                Button(firstTime ? "Skip for now" : "Close") {
                    showSetup = false
                }
                .buttonStyle(BourbonSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
                .help("Close setup. Bourbon may not work until required setup items are installed.")

                Spacer()

                Button("Let me do it manually") {
                    showManualSetup.toggle()
                }
                .buttonStyle(BourbonSecondaryButtonStyle())
                .help("Show manual setup instructions.")

                Button("Install for me") {
                    continueFromDependencies()
                }
                .buttonStyle(BourbonPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .help("Install the missing setup item.")
            }
        }
    }

    private var welcomeContent: some View {
        VStack(spacing: 18) {
            Image(systemName: "wineglass.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(BourbonStyle.amber)

            VStack(spacing: 6) {
                Text("Welcome to Bourbon")
                    .font(.largeTitle.bold())
                Text("Run your favorite Windows applications on macOS.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text("Create your first Bottle")
                .font(.headline)

            Button("What is a bottle?") {
                showBottleExplanation = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(BourbonStyle.amber)
            .help("Learn why Bourbon uses bottles.")

            HStack(spacing: 18) {
                Button(firstTime ? "Skip for now" : "Close") {
                    showSetup = false
                }
                .buttonStyle(BourbonSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button("Create Bottle") {
                    finishOnboardingAndCreateBottle()
                }
                .buttonStyle(BourbonPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .help("Create your first bottle and continue to the installer picker.")
            }
            .padding(.top, 8)
        }
        .sheet(isPresented: $showBottleExplanation) {
            BourbonPanelBackdrop {
                BourbonFloatingPanel(maxWidth: 420) {
                    VStack(spacing: 14) {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(BourbonStyle.amber)
                        Text("What is a Bottle?")
                            .font(.title2.bold())
                        Text(
                            "A Bottle is an isolated Windows environment.\n\n" +
                            "Each Bottle contains its own Windows files, settings, installed applications, " +
                            "and configuration.\n\n" +
                            "Think of it like giving every Windows application its own tiny Windows computer."
                        )
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                        Button("Got it") {
                            showBottleExplanation = false
                        }
                        .buttonStyle(BourbonPrimaryButtonStyle())
                    }
                }
            }
            .frame(width: 520, height: 420)
        }
    }

    private var displayNameContent: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(BourbonStyle.amber)

            VStack(spacing: 6) {
                Text("Welcome, what should we call you?")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("This name personalizes Bourbon on this Mac.")
                    .foregroundStyle(.secondary)
            }

            TextField("Display name", text: $draftDisplayName)
                .textFieldStyle(.roundedBorder)
                .disabled(isCreatingAccount)

            HStack {
                if !firstTime {
                    Button("Close") {
                        showSetup = false
                    }
                    .buttonStyle(BourbonSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                }

                Spacer()

                Button("Next") {
                    storedDisplayName = sanitizedDisplayName
                    hasChosenDisplayName = true
                }
                .buttonStyle(BourbonPrimaryButtonStyle())
                .disabled(sanitizedDisplayName.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var legalAcceptanceContent: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Please read and accept Bourbon’s terms.")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("These policies explain what Bourbon provides and how community features stay safe.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                ForEach(BourbonLegalDocument.allCases) { document in
                    Button {
                        document.open()
                    } label: {
                        Label(document.fileName, systemImage: "doc.text")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(BourbonSecondaryButtonStyle())
                    .help("Open \(document.fileName).")
                }
            }

            Toggle("I have read and agree to Bourbon’s terms and policies.", isOn: $acceptedTerms)
                .toggleStyle(.checkbox)
                .disabled(isCreatingAccount)

            if let accountError {
                Text(accountError)
                    .font(.caption)
                    .foregroundStyle(BourbonStyle.amber)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Button("Back") {
                    hasChosenDisplayName = false
                }
                .buttonStyle(BourbonSecondaryButtonStyle())
                .disabled(isCreatingAccount)

                Spacer()

                Button {
                    hasAcceptedLegalDocuments = true
                    legacyAcceptedLegalTerms = true
                } label: {
                    Text("Accept Terms")
                }
                .buttonStyle(BourbonPrimaryButtonStyle())
                .disabled(!acceptedTerms || isCreatingAccount)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder
    private var licenseCreationContent: some View {
        if let activatedLicenseKey {
            licenseKeyContent(activatedLicenseKey)
        } else {
            licenseActivationContent
        }
    }

    private var licenseActivationContent: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(BourbonStyle.amber)

            VStack(spacing: 6) {
                Text("Create your free Bourbon license")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(
                    "Bourbon stores your license securely on this Mac. Keep a copy of your " +
                    "license key somewhere safe so you can restore it later."
                )
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let accountError {
                Text(accountError)
                    .font(.caption)
                    .foregroundStyle(BourbonStyle.amber)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Button("Back") {
                    hasAcceptedLegalDocuments = false
                }
                .buttonStyle(BourbonSecondaryButtonStyle())
                .disabled(isCreatingAccount)

                Spacer()

                Button {
                    createFreeAccount()
                } label: {
                    if isCreatingAccount {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Create Free Account")
                    }
                }
                .buttonStyle(BourbonPrimaryButtonStyle())
                .disabled(isCreatingAccount)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func licenseKeyContent(_ key: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(BourbonStyle.amber)

            VStack(spacing: 6) {
                Text("Your Bourbon License")
                    .font(.largeTitle.bold())
                Text(
                    "This is your Bourbon license key. Bourbon stores it securely on this Mac, " +
                    "but keep a copy somewhere safe in case you ever need to restore your license."
                )
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text(key)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 10) {
                Button {
                    saveLicenseKey(key)
                } label: {
                    Label("Save License Key", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(BourbonSecondaryButtonStyle())

                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(key, forType: .string)
                }
                .buttonStyle(BourbonSecondaryButtonStyle())
            }

            Button("Continue") {
                hasCreatedLicense = true
                legacyCreatedFreeLicense = true
                activatedLicenseKey = nil
            }
            .buttonStyle(BourbonPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
    }

    private func saveLicenseKey(_ key: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Bourbon-License.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let contents = "Bourbon License Key\n\n\(key)\n\nKeep this file somewhere safe. " +
            "You can use this key to restore your Bourbon license if the local copy is lost.\n"
        try? contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func checkInstallStatus() {
        rosettaInstalled = Rosetta2.isRosettaInstalled
        installStatusRequestID = UUID()
        let requestID = installStatusRequestID
        WhiskyWineInstaller.recordRuntimeEvent("runtime.bootstrap.setup_check.started")
        Task {
            let installed = await Task.detached(priority: .userInitiated) {
                WhiskyWineInstaller.isWhiskyWineInstalled()
            }.value
            guard requestID == installStatusRequestID, !Task.isCancelled else { return }
            whiskyWineInstalled = installed
            hasInstalledDependencies = rosettaInstalled == true && installed
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.bootstrap.setup_check.completed",
                detail: "ready=\(installed)"
            )
        }
    }

    private var dependenciesInstalled: Bool {
        rosettaInstalled == true && whiskyWineInstalled == true
    }

    private var currentStep: OnboardingStep {
        if hasCompletedFirstRunOnboarding {
            return .welcomeHome
        }
        if !hasSeenWelcome {
            return .welcome
        }
        if !dependenciesAvailable {
            return .dependencies
        }
        if !hasChosenDisplayName || storedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .displayName
        }
        if !hasAcceptedLegalDocuments {
            return .legal
        }
        if !hasCreatedLicense || !hasUsableLicense {
            return .license
        }
        return .welcomeHome
    }

    private var sanitizedDisplayName: String {
        draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var runtimeReady: Bool? {
        guard rosettaInstalled != nil && whiskyWineInstalled != nil else { return nil }
        return dependenciesAvailable
    }

    private var dependenciesAvailable: Bool {
        dependenciesInstalled || (hasInstalledDependencies && rosettaInstalled == true && whiskyWineInstalled == true)
    }

    private func continueFromDependencies() {
        if rosettaInstalled != true {
            path.append(.rosetta)
            return
        }

        if whiskyWineInstalled != true {
            path.append(.whiskyWineDownload)
            return
        }

        hasInstalledDependencies = true
    }

    private func finishOnboardingAndCreateBottle() {
        hasCompletedFirstRunOnboarding = true
        showSetup = false
        showBottleCreation = true
    }

    private func migrateLegacyOnboardingFlags() {
        if draftDisplayName.isEmpty {
            draftDisplayName = storedDisplayName
        }

        if !storedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hasChosenDisplayName = true
        }
        if legacyAcceptedLegalTerms {
            hasAcceptedLegalDocuments = true
        }
        if legacyCreatedFreeLicense {
            hasCreatedLicense = true
        }
        acceptedTerms = hasAcceptedLegalDocuments
    }

    private func createFreeAccount() {
        accountError = nil
        isCreatingAccount = true
        storedDisplayName = sanitizedDisplayName

        Task {
            do {
                let record = try await BourbonLicenseAPI.activateFreeLicense(
                    displayName: sanitizedDisplayName
                )
                try await LicenseKeychainStore.saveAsync(record)
                await MainActor.run {
                    activatedLicenseKey = record.licenseKey ?? "\(record.publicLicenseId).\(record.licenseToken)"
                    hasUsableLicense = true
                    isCreatingAccount = false
                }
            } catch {
                await MainActor.run {
                    isCreatingAccount = false
                    accountError = "Could not create your free account. Check your connection and try again."
                }
            }
        }
    }

    private func refreshLicenseState() async {
        let record = await LicenseKeychainStore.currentLicenseAsync()
        guard !Task.isCancelled else { return }
        hasUsableLicense = record != nil
        if hasUsableLicense {
            hasCreatedLicense = true
        }
    }
}

enum BourbonLegalDocument: String, CaseIterable, Identifiable {
    case terms = "TERMS_OF_SERVICE.md"
    case privacy = "PRIVACY_POLICY.md"
    case acceptableUse = "ACCEPTABLE_USE_POLICY.md"
    case communityUploads = "COMMUNITY_UPLOAD_GUIDELINES.md"
    case copyright = "COPYRIGHT_DMCA_POLICY.md"
    case moderation = "CONTENT_MODERATION_POLICY.md"
    case security = "SECURITY_MALWARE_POLICY.md"
    case disclaimer = "DISCLAIMER.md"

    var id: String { rawValue }
    var fileName: String { rawValue }

    func open() {
        let file = URL(fileURLWithPath: rawValue)
        if let bundledURL = Bundle.main.url(
            forResource: file.deletingPathExtension().lastPathComponent,
            withExtension: file.pathExtension
        ) {
            NSWorkspace.shared.open(bundledURL)
            return
        }

        let sourceURL = URL(fileURLWithPath: "Source/Whisky/Legal").appending(path: rawValue)
        if FileManager.default.fileExists(atPath: sourceURL.path) {
            NSWorkspace.shared.open(sourceURL)
        }
    }
}

struct ManualSetupView: View {
    let rosettaInstalled: Bool?
    let whiskyWineInstalled: Bool?

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            if rosettaInstalled != true {
                ManualDependencyView(
                    name: "Rosetta",
                    reason: "Rosetta lets Bourbon run Intel Wine tools on Apple silicon Macs.",
                    command: "/usr/sbin/softwareupdate --install-rosetta --agree-to-license"
                )
            }

            if whiskyWineInstalled != true {
                VStack(alignment: .center, spacing: 4) {
                    Text("BourbonWine")
                        .font(.headline)
                    Text("BourbonWine is the Wine runtime Bourbon uses to run Windows apps.")
                        .foregroundStyle(.secondary)
                    Text(
                        "Use Install for me to download the supported runtime, " +
                        "or install a compatible local archive from the next screen."
                    )
                        .foregroundStyle(.secondary)
                }
            }

            Text(
                "Bourbon may not work without required setup items. " +
                "Windows apps may fail to open or bottles may not finish creating."
            )
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

struct ManualDependencyView: View {
    let name: String
    let reason: String
    let command: String

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(name)
                .font(.headline)
            Text(reason)
                .foregroundStyle(.secondary)
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            HStack {
                Button("Copy command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
                .buttonStyle(BourbonSecondaryButtonStyle())
                .help("Copy this command to the clipboard.")

                Button("Open Terminal") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                }
                .buttonStyle(BourbonSecondaryButtonStyle())
                .help("Open Terminal so you can run the command.")
            }
        }
    }
}

struct InstallStatusView: View {
    @Binding var isInstalled: Bool?
    @Binding var shouldCheckInstallStatus: Bool
    @State var showUninstall: Bool = false
    @State var name: String
    @State var text: String = String(localized: "setup.install.checking")

    var body: some View {
        SetupStatusRow(title: name, subtitle: String.init(format: text, name), isInstalled: isInstalled) {
            if isInstalled == true && showUninstall {
                Button("Remove") {
                    uninstall()
                }
                .buttonStyle(BourbonSecondaryButtonStyle())
                .help("Remove BourbonWine so it can be installed again.")
            }
        }
        .onChange(of: isInstalled) {
            if let installed = isInstalled {
                if installed {
                    text = String(localized: "setup.install.installed")
                } else {
                    text = String(localized: "setup.install.notInstalled")
                }
            } else {
                text = String(localized: "setup.install.checking")
            }
        }
    }

    func uninstall() {
        if name == "BourbonWine" {
            WhiskyWineInstaller.uninstall()
        }

        shouldCheckInstallStatus.toggle()
    }
}

struct SetupStatusRow<Accessory: View>: View {
    let title: String
    let subtitle: String
    let isInstalled: Bool?
    @ViewBuilder var accessory: Accessory

    init(
        title: String,
        subtitle: String,
        isInstalled: Bool?,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isInstalled = isInstalled
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            statusIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            accessory
        }
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if let isInstalled {
            Image(systemName: isInstalled ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(isInstalled ? .green : BourbonStyle.amber)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }
}

struct BourbonLicenseRecord: Codable, Sendable {
    let publicLicenseId: String
    let licenseToken: String
    let licenseKey: String?
    let installId: String
    let displayName: String
    let status: String
    let messages: [String]
    let permissions: [String]
    let warnings: [String]
    let strikes: Int

    private enum CodingKeys: String, CodingKey {
        case publicLicenseId
        case licenseToken
        case licenseKey
        case installId
        case displayName
        case status
        case messages
        case permissions
        case warnings
        case strikes
    }

    init(
        publicLicenseId: String,
        licenseToken: String,
        licenseKey: String? = nil,
        installId: String,
        displayName: String,
        status: String,
        messages: [String],
        permissions: [String],
        warnings: [String],
        strikes: Int
    ) {
        self.publicLicenseId = publicLicenseId
        self.licenseToken = licenseToken
        self.licenseKey = licenseKey
        self.installId = installId
        self.displayName = displayName
        self.status = status
        self.messages = messages
        self.permissions = permissions
        self.warnings = warnings
        self.strikes = strikes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        publicLicenseId = try container.decode(String.self, forKey: .publicLicenseId)
        licenseToken = try container.decode(String.self, forKey: .licenseToken)
        licenseKey = try container.decodeIfPresent(String.self, forKey: .licenseKey)
        installId = try container.decode(String.self, forKey: .installId)
        displayName = try container.decode(String.self, forKey: .displayName)
        status = try container.decode(String.self, forKey: .status)
        messages = try container.decode([String].self, forKey: .messages)
        permissions = try container.decode([String].self, forKey: .permissions)
        warnings = try container.decode([String].self, forKey: .warnings)
        strikes = try container.decode(Int.self, forKey: .strikes)
    }
}

enum LicenseValidationStatus: String, Codable {
    case valid
    case paused
    case deleted
    case banned
    case revoked
    case expired
    case scheduledForDeletion
    case unknown
}

struct LicenseValidationResult: Codable {
    let licenseId: String
    let status: LicenseValidationStatus
    let isValid: Bool
    let allowed: Bool
    let revoked: Bool
    let warnings: [String]
    let reason: String?
    let appealAllowed: Bool
    let deletionScheduledAt: Date?
    let checkedAt: Date

    var title: String {
        switch status {
        case .valid:
            return "License active"
        case .paused:
            return "License paused"
        case .deleted:
            return "License unavailable"
        case .banned:
            return "Account action required"
        case .revoked:
            return "License revoked"
        case .expired:
            return "License expired"
        case .scheduledForDeletion:
            return "License scheduled for deletion"
        case .unknown:
            return "License unavailable"
        }
    }
}

enum BourbonLicenseAPI {
    private static let acceptedLegalVersion = "2026-06-27"

    static func activateFreeLicense(displayName: String) async throws -> BourbonLicenseRecord {
        let installId = try LicenseKeychainStore.installID()
        let acceptedAt = Date()
        var request = URLRequest(url: BourbonAPIConfiguration.licenseActivationURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(LicenseActivationRequest(
            displayName: displayName,
            appVersion: appVersion,
            macosVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: currentArchitecture,
            installId: installId,
            acceptedLegalVersion: acceptedLegalVersion,
            acceptedLegalAt: acceptedAt
        ))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession(configuration: configuration).data(for: request)
        } catch {
            throw LicenseActivationError.network
        }

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw LicenseActivationError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(LicenseActivationResponse.self, from: data)
        let displayedLicenseKey = decoded.licenseKey ?? "\(decoded.publicLicenseId).\(decoded.licenseToken)"
        guard !decoded.publicLicenseId.isEmpty,
              !decoded.licenseToken.isEmpty else {
            throw LicenseActivationError.invalidResponse
        }

        return BourbonLicenseRecord(
            publicLicenseId: decoded.publicLicenseId,
            licenseToken: decoded.licenseToken,
            licenseKey: displayedLicenseKey,
            installId: installId,
            displayName: decoded.displayName,
            status: decoded.status,
            messages: decoded.messages,
            permissions: decoded.permissions,
            warnings: [],
            strikes: 0
        )
    }

    static func validateCurrentLicense() async throws -> LicenseValidationResult {
        let credential = try await LicenseKeychainStore.validationCredential()
        let license = credential.record
        let token = credential.token

        var request = URLRequest(url: BourbonAPIConfiguration.licenseValidationURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(LicenseValidationRequest(
            licenseId: license.publicLicenseId,
            licenseToken: token
        ))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseActivationError.invalidResponse
        }
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 404 {
            await LicenseKeychainStore.clearObsoleteLicenseState()
            throw LicenseActivationError.licenseReset
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw LicenseActivationError.invalidResponse
        }

        let decoder = BourbonLicenseAPI.decoder()
        return try decoder.decode(LicenseValidationResult.self, from: data)
    }

    static func recoverLicense(key: String) async throws -> LicenseRecoveryOutcome {
        let normalizedKey = normalizeRecoveryKey(key)
        var request = URLRequest(url: BourbonAPIConfiguration.licenseRecoveryURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(LicenseRecoveryRequest(licenseKey: normalizedKey))

        let (data, httpResponse) = try await recoveryResponse(for: request)
        let decoded = try decodeRecoveryResponse(data: data, statusCode: httpResponse.statusCode)
        guard let validation = decoded.validationResult else {
            throw LicenseActivationError.invalidResponse
        }
        if httpResponse.statusCode == 403 {
            throw LicenseActivationError.blocked(validation)
        }
        guard let publicLicenseId = decoded.publicLicenseId,
              let licenseToken = decoded.licenseToken else {
            throw LicenseActivationError.invalidResponse
        }

        let record = BourbonLicenseRecord(
            publicLicenseId: publicLicenseId,
            licenseToken: licenseToken,
            licenseKey: decoded.licenseKey,
            installId: try LicenseKeychainStore.installID(),
            displayName: decoded.displayName ?? "Bourbon User",
            status: decoded.status?.rawValue ?? "Free",
            messages: decoded.messages ?? [],
            permissions: decoded.permissions ?? [],
            warnings: validation.warnings,
            strikes: 0
        )
        print("License recovery server accepted credential")
        return LicenseRecoveryOutcome(record: record, validation: validation)
    }

    private static func recoveryResponse(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession(configuration: configuration).data(for: request)
        } catch {
            throw LicenseActivationError.network
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseActivationError.invalidResponse
        }
        return (data, httpResponse)
    }

    private static func decodeRecoveryResponse(data: Data, statusCode: Int) throws -> LicenseRecoveryResponse {
        if statusCode == 429 {
            throw LicenseActivationError.rateLimited
        }
        if statusCode == 400 || statusCode == 401 {
            throw LicenseActivationError.invalidLicense
        }
        guard 200..<300 ~= statusCode || statusCode == 403 else {
            throw LicenseActivationError.service(status: statusCode)
        }

        do {
            return try decoder().decode(LicenseRecoveryResponse.self, from: data)
        } catch {
            print("License recovery response decoding failed")
            throw LicenseActivationError.invalidResponse
        }
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date"
            )
        }
        return decoder
    }

    private static func normalizeRecoveryKey(_ value: String) -> String {
        let pattern = #"BRBN-[A-Za-z0-9-]{8,64}\.[A-Za-z0-9_-]{64}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = regex.matches(in: value, range: range)
        guard matches.count == 1, let matchRange = Range(matches[0].range, in: value) else {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(value[matchRange])
    }

    static func submitAppeal(for result: LicenseValidationResult) async throws {
        let credential = try await LicenseKeychainStore.validationCredential()
        let token = credential.token

        var request = URLRequest(url: BourbonAPIConfiguration.licenseAppealURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(LicenseAppealRequest(
            licenseId: result.licenseId,
            licenseToken: token,
            status: result.status.rawValue,
            reason: result.reason
        ))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        let (_, response) = try await URLSession(configuration: configuration).data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw LicenseActivationError.invalidResponse
        }
    }

    private static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        return "\(version) (\(build))"
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}

private struct LicenseActivationRequest: Encodable {
    let displayName: String
    let appVersion: String
    let macosVersion: String
    let architecture: String
    let installId: String
    let acceptedLegalVersion: String
    let acceptedLegalAt: Date
}

private struct LicenseValidationRequest: Encodable {
    let licenseId: String
    let licenseToken: String
}

private struct LicenseRecoveryRequest: Encodable {
    let licenseKey: String
}

struct LicenseRecoveryOutcome {
    let record: BourbonLicenseRecord
    let validation: LicenseValidationResult
}

private struct LicenseRecoveryResponse: Decodable {
    let licenseId: String?
    let status: LicenseValidationStatus?
    let isValid: Bool?
    let allowed: Bool?
    let revoked: Bool?
    let warnings: [String]?
    let reason: String?
    let appealAllowed: Bool?
    let deletionScheduledAt: Date?
    let checkedAt: Date?
    let publicLicenseId: String?
    let licenseToken: String?
    let licenseKey: String?
    let displayName: String?
    let messages: [String]?
    let permissions: [String]?

    var validationResult: LicenseValidationResult? {
        guard let licenseId, let status, let isValid, let allowed, let revoked,
              let warnings, let appealAllowed, let checkedAt else {
            return nil
        }
        return LicenseValidationResult(
            licenseId: licenseId,
            status: status,
            isValid: isValid,
            allowed: allowed,
            revoked: revoked,
            warnings: warnings,
            reason: reason,
            appealAllowed: appealAllowed,
            deletionScheduledAt: deletionScheduledAt,
            checkedAt: checkedAt
        )
    }
}

private struct LicenseAppealRequest: Encodable {
    let licenseId: String
    let licenseToken: String
    let status: String
    let reason: String?
}

private struct LicenseActivationResponse: Decodable {
    let publicLicenseId: String
    let licenseToken: String
    let licenseKey: String?
    let displayName: String
    let status: String
    let messages: [String]
    let permissions: [String]
}

enum BourbonAPIConfiguration {
    private struct LocalConfig: Decodable {
        let apiBaseURL: String?
        let licenseAPIBaseURL: String?
    }

    static var licenseActivationURL: URL {
        baseURL.appending(path: "licenses/activate")
    }

    static var licenseValidationURL: URL {
        baseURL.appending(path: "license/validate")
    }

    static var licenseRecoveryURL: URL {
        baseURL.appending(path: "license/recover")
    }

    static var licenseAppealURL: URL {
        baseURL.appending(path: "license/appeal")
    }

    private static var baseURL: URL {
        if let configuredURL = localConfigURL {
            return configuredURL
        }

        if let url = environmentBaseURL {
            return url
        }

        guard let url = URL(string: "https://api.getbourbon.app") else {
            preconditionFailure("Invalid default Bourbon API URL.")
        }
        return url
    }

    private static var environmentBaseURL: URL? {
        guard let environmentURL = ProcessInfo.processInfo.environment["BOURBON_API_BASE_URL"] else {
            return nil
        }
        return URL(string: environmentURL)
    }

    private static var localConfigURL: URL? {
        let candidates = [
            URL(fileURLWithPath: "AdminLocalConfig.json"),
            URL(fileURLWithPath: "Source/Whisky/Admin/LocalOnly/AdminLocalConfig.json")
        ]

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            guard let data = try? Data(contentsOf: candidate),
                  let config = try? JSONDecoder().decode(LocalConfig.self, from: data),
                  let rawURL = config.licenseAPIBaseURL ?? config.apiBaseURL,
                  let url = URL(string: rawURL) else {
                continue
            }
            return url
        }

        return nil
    }
}

struct BourbonLicenseCredential: Sendable {
    let record: BourbonLicenseRecord
    let token: String
}

// swiftlint:disable:next type_body_length
enum LicenseKeychainStore {
    private static let service = "com.unblockerfire.Bourbon.license"
    private static let legacyLicenseAccount = "license-record"
    private static var defaults: UserDefaults { .standard }
    private static var bundleIdentifier: String? { Bundle.main.bundleIdentifier }

    private enum DefaultsKey {
        static let publicLicenseId = "bourbon.publicLicenseId"
        static let installId = "bourbon.installId"
        static let licenseDisplayName = "bourbon.licenseDisplayName"
        static let licenseStatus = "bourbon.licenseStatus"
        static let licenseMessages = "bourbon.licenseMessages"
        static let licensePermissions = "bourbon.licensePermissions"
        static let licenseWarnings = "bourbon.licenseWarnings"
        static let licenseStrikes = "bourbon.licenseStrikes"
    }

    static func save(_ record: BourbonLicenseRecord) throws {
        let account = BourbonLicenseStoragePolicy.tokenAccount(
            for: bundleIdentifier ?? BourbonLicenseStoragePolicy.productionBundleIdentifier
        )
        try updateLicenseToken(record.licenseToken, account: account)
        guard try readLicenseToken(account: account) == record.licenseToken else {
            throw LicenseActivationError.keychain(errSecDecode)
        }
        savePublicMetadata(record)
    }

    static func saveAsync(_ record: BourbonLicenseRecord) async throws {
        try await Task.detached(priority: .userInitiated) {
            try save(record)
        }.value
    }

    static func currentLicense() -> BourbonLicenseRecord? {
        (try? credential())?.record
    }

    static func currentPublicLicenseID() -> String? {
        selectedPublicMetadata()?.record.publicLicenseId
    }

    static func currentLicenseAsync() async -> BourbonLicenseRecord? {
        await Task.detached(priority: .userInitiated) {
            currentLicense()
        }.value
    }

    static func validationCredential() async throws -> BourbonLicenseCredential {
        try await Task.detached(priority: .userInitiated) {
            try credential()
        }.value
    }

    static func installID() throws -> String {
        if let existing = defaults.string(forKey: DefaultsKey.installId),
           !existing.isEmpty {
            return existing
        }

        let newID = UUID().uuidString
        defaults.set(newID, forKey: DefaultsKey.installId)
        return newID
    }

    static func clearObsoleteLicenseState() async {
        await Task.detached(priority: .utility) {
            performObsoleteStateCleanup()
        }.value
    }

    private static func performObsoleteStateCleanup() {
        let isDiagnostic = BourbonLicenseStoragePolicy.isDiagnostic(bundleIdentifier: bundleIdentifier)
        let metadataIdentifier = isDiagnostic
            ? BourbonLicenseStoragePolicy.diagnosticBundleIdentifier
            : BourbonLicenseStoragePolicy.productionBundleIdentifier
        let account = BourbonLicenseStoragePolicy.tokenAccount(for: metadataIdentifier)
        delete(account: account)
        if BourbonLicenseStoragePolicy.mayMutateProductionState(bundleIdentifier: bundleIdentifier) {
            delete(account: legacyLicenseAccount)
        } else {
            BourbonLicenseDiagnostics.record(
                "license.production_state.preserved",
                detail: "reason=diagnostic_cleanup_blocked"
            )
        }
        removePublicMetadata(from: defaults)
    }

    private static func credential() throws -> BourbonLicenseCredential {
        guard let metadata = selectedPublicMetadata() else {
            throw LicenseActivationError.missingToken
        }
        let account = BourbonLicenseStoragePolicy.tokenAccount(for: metadata.bundleIdentifier)
        let token = try readLicenseToken(account: account)
        BourbonLicenseDiagnostics.record(
            "license.storage.resolved",
            detail: "metadata=\(metadata.bundleIdentifier) token_account=\(account)"
        )
        return BourbonLicenseCredential(record: metadata.record, token: token)
    }

    private static func selectedPublicMetadata() -> (bundleIdentifier: String, record: BourbonLicenseRecord)? {
        let identifiers = BourbonLicenseStoragePolicy.metadataBundleIdentifiers(for: bundleIdentifier)
        var records: [String: BourbonLicenseRecord] = [:]
        for identifier in identifiers {
            let candidateDefaults: UserDefaults?
            if identifier == bundleIdentifier {
                candidateDefaults = defaults
            } else {
                candidateDefaults = UserDefaults(suiteName: identifier)
            }
            if let candidateDefaults,
               let record = publicMetadataRecord(from: candidateDefaults) {
                records[identifier] = record
            }
        }
        guard let selectedIdentifier = BourbonLicenseStoragePolicy.resolvedMetadataBundleIdentifier(
            for: bundleIdentifier,
            availableBundleIdentifiers: Set(records.keys)
        ), let record = records[selectedIdentifier] else {
            return nil
        }
        return (selectedIdentifier, record)
    }

    private static func savePublicMetadata(_ record: BourbonLicenseRecord) {
        defaults.set(record.publicLicenseId, forKey: DefaultsKey.publicLicenseId)
        defaults.set(record.installId, forKey: DefaultsKey.installId)
        defaults.set(record.displayName, forKey: DefaultsKey.licenseDisplayName)
        defaults.set(record.status, forKey: DefaultsKey.licenseStatus)
        defaults.set(record.messages, forKey: DefaultsKey.licenseMessages)
        defaults.set(record.permissions, forKey: DefaultsKey.licensePermissions)
        defaults.set(record.warnings, forKey: DefaultsKey.licenseWarnings)
        defaults.set(record.strikes, forKey: DefaultsKey.licenseStrikes)
    }

    private static func removePublicMetadata(from defaults: UserDefaults) {
        for key in [
            DefaultsKey.publicLicenseId,
            DefaultsKey.licenseDisplayName,
            DefaultsKey.licenseStatus,
            DefaultsKey.licenseMessages,
            DefaultsKey.licensePermissions,
            DefaultsKey.licenseWarnings,
            DefaultsKey.licenseStrikes
        ] {
            defaults.removeObject(forKey: key)
        }
    }

    private static func publicMetadataRecord(from defaults: UserDefaults) -> BourbonLicenseRecord? {
        guard let publicLicenseId = defaults.string(forKey: DefaultsKey.publicLicenseId),
              !publicLicenseId.isEmpty else {
            return nil
        }

        return BourbonLicenseRecord(
            publicLicenseId: publicLicenseId,
            licenseToken: "",
            licenseKey: nil,
            installId: defaults.string(forKey: DefaultsKey.installId) ?? "",
            displayName: defaults.string(forKey: DefaultsKey.licenseDisplayName) ?? "Bourbon User",
            status: defaults.string(forKey: DefaultsKey.licenseStatus) ?? "Active",
            messages: defaults.stringArray(forKey: DefaultsKey.licenseMessages) ?? ["Welcome to Bourbon."],
            permissions: defaults.stringArray(forKey: DefaultsKey.licensePermissions)
            ?? ["Distillery: Enabled", "Uploads: Enabled"],
            warnings: defaults.stringArray(forKey: DefaultsKey.licenseWarnings) ?? [],
            strikes: defaults.integer(forKey: DefaultsKey.licenseStrikes)
        )
    }

    private static func readLicenseToken(account: String) throws -> String {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let token = String(data: data, encoding: .utf8),
                  !token.isEmpty else {
                throw LicenseActivationError.keychain(errSecDecode)
            }
            return token
        case errSecItemNotFound:
            throw LicenseActivationError.missingToken
        default:
            BourbonLicenseDiagnostics.record(
                "license.keychain.read.failed",
                detail: "status=\(status) authentication_ui=disabled"
            )
            throw LicenseActivationError.keychain(status)
        }
    }

    private static func updateLicenseToken(_ token: String, account: String) throws {
        guard !token.isEmpty else { return }
        var query = baseQuery(account: account)
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }
        if status == errSecItemNotFound {
            try add(Data(token.utf8), account: account)
            return
        }
        throw LicenseActivationError.keychain(status)
    }

    private static func add(_ data: Data, account: String) throws {
        var addQuery = baseQuery(account: account)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LicenseActivationError.keychain(status)
        }
    }

    private static func delete(account: String) {
        var query = baseQuery(account: account)
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            BourbonLicenseDiagnostics.record(
                "license.keychain.delete.failed",
                detail: "status=\(status) authentication_ui=disabled"
            )
            return
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum LicenseActivationError: Error {
    case invalidResponse
    case network
    case invalidLicense
    case rateLimited
    case service(status: Int)
    case keychain(OSStatus)
    case missingToken
    case licenseReset
    case blocked(LicenseValidationResult)
}

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

import SwiftUI
import Security
import WhiskyKit

// swiftlint:disable file_length
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
        BourbonPage {
            ScrollView {
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
                .padding(34)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity, minHeight: 520)
            }
        }
        .navigationTitle("Welcome")
        .onAppear {
            migrateLegacyOnboardingFlags()
            checkInstallStatus()
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

            HStack {
                Button(firstTime ? "Skip for now" : "Close") {
                    showSetup = false
                }
                .buttonStyle(BourbonSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create Bottle") {
                    finishOnboardingAndCreateBottle()
                }
                .buttonStyle(BourbonPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .help("Create your first bottle and continue to the installer picker.")
            }
        }
        .sheet(isPresented: $showBottleExplanation) {
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
            .padding(28)
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

    private var licenseCreationContent: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(BourbonStyle.amber)

            VStack(spacing: 6) {
                Text("Create your free Bourbon license")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Your public license ID can be shown in Bourbon. Your private token stays in Keychain.")
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

    func checkInstallStatus() {
        rosettaInstalled = Rosetta2.isRosettaInstalled
        whiskyWineInstalled = WhiskyWineInstaller.isWhiskyWineInstalled()
        hasInstalledDependencies = dependenciesInstalled
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
        if !hasCreatedLicense || LicenseKeychainStore.currentLicense() == nil {
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
        dependenciesInstalled
        || (hasInstalledDependencies && Rosetta2.isRosettaInstalled && WhiskyWineInstaller.isWhiskyWineInstalled())
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
        if legacyCreatedFreeLicense || LicenseKeychainStore.currentLicense() != nil {
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
                try LicenseKeychainStore.save(record)
                await MainActor.run {
                    hasCreatedLicense = true
                    legacyCreatedFreeLicense = true
                    isCreatingAccount = false
                }
            } catch {
                do {
                    let record = try BourbonLicenseAPI.mockActivateFreeLicense(displayName: sanitizedDisplayName)
                    try LicenseKeychainStore.save(record)
                    await MainActor.run {
                        hasCreatedLicense = true
                        legacyCreatedFreeLicense = true
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

struct BourbonLicenseRecord: Codable {
    let publicLicenseId: String
    let licenseToken: String
    let installId: String
    let displayName: String
    let status: String
    let messages: [String]
    let permissions: [String]
    let warnings: [String]
    let strikes: Int
}

enum LicenseValidationStatus: String, Codable {
    case valid
    case paused
    case deleted
    case banned
    case expired
    case scheduledForDeletion
    case unknown
}

struct LicenseValidationResult: Codable {
    let licenseId: String
    let status: LicenseValidationStatus
    let isValid: Bool
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
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw LicenseActivationError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(LicenseActivationResponse.self, from: data)
        guard !decoded.publicLicenseId.isEmpty,
              !decoded.licenseToken.isEmpty else {
            throw LicenseActivationError.invalidResponse
        }

        return BourbonLicenseRecord(
            publicLicenseId: decoded.publicLicenseId,
            licenseToken: decoded.licenseToken,
            installId: installId,
            displayName: decoded.displayName,
            status: decoded.status,
            messages: decoded.messages,
            permissions: decoded.permissions,
            warnings: [],
            strikes: 0
        )
    }

    static func mockActivateFreeLicense(displayName: String) throws -> BourbonLicenseRecord {
        let installId = try LicenseKeychainStore.installID()
        let licenseNumber = UserDefaults.standard.integer(forKey: "mockLicenseCounter") + 1
        UserDefaults.standard.set(licenseNumber, forKey: "mockLicenseCounter")
        let publicLicenseId = "BRBN-\(String(format: "%08d", licenseNumber))"

        return BourbonLicenseRecord(
            publicLicenseId: publicLicenseId,
            licenseToken: UUID().uuidString,
            installId: installId,
            displayName: displayName,
            status: "Free",
            messages: ["Local mock account created. Online activation can be connected later."],
            permissions: ["distillery", "local-installs"],
            warnings: [],
            strikes: 0
        )
    }

    static func validateCurrentLicense() async throws -> LicenseValidationResult? {
        guard let license = LicenseKeychainStore.currentLicense(),
              !license.publicLicenseId.isEmpty else {
            return nil
        }

        guard let token = LicenseKeychainStore.readLicenseToken() else {
            return LicenseValidationResult(
                licenseId: license.publicLicenseId,
                status: .unknown,
                isValid: false,
                reason: "Bourbon could not find the private license token for this installation.",
                appealAllowed: false,
                deletionScheduledAt: nil,
                checkedAt: Date()
            )
        }

        if !BourbonAPIConfiguration.hasConfiguredBackend {
            return mockValidateLicense(licenseId: license.publicLicenseId)
        }

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

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw LicenseActivationError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LicenseValidationResult.self, from: data)
    }

    static func submitAppeal(for result: LicenseValidationResult) async throws {
        guard let token = LicenseKeychainStore.readLicenseToken() else {
            throw LicenseActivationError.invalidResponse
        }

        if !BourbonAPIConfiguration.hasConfiguredBackend {
            print("License appeal captured locally for development")
            return
        }

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

    private static func mockValidateLicense(licenseId: String) -> LicenseValidationResult {
        // Future backend: replace this local development result with
        // POST /license/validate once the license service is available.
        LicenseValidationResult(
            licenseId: licenseId,
            status: .valid,
            isValid: true,
            reason: nil,
            appealAllowed: false,
            deletionScheduledAt: nil,
            checkedAt: Date()
        )
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

private struct LicenseAppealRequest: Encodable {
    let licenseId: String
    let licenseToken: String
    let status: String
    let reason: String?
}

private struct LicenseActivationResponse: Decodable {
    let publicLicenseId: String
    let licenseToken: String
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

    static var licenseAppealURL: URL {
        baseURL.appending(path: "license/appeal")
    }

    static var hasConfiguredBackend: Bool {
        localConfigURL != nil || environmentBaseURL != nil
    }

    private static var baseURL: URL {
        if let configuredURL = localConfigURL {
            return configuredURL
        }

        if let url = environmentBaseURL {
            return url
        }

        return URL(string: "https://api.bourbon.app")!
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

enum LicenseKeychainStore {
    private static let service = "com.unblockerfire.Bourbon.license"
    private static let legacyLicenseAccount = "license-record"
    private static let licenseTokenAccount = "license-token"
    private static var defaults: UserDefaults { .standard }

    private enum DefaultsKey {
        static let publicLicenseId = "bourbon.publicLicenseId"
        static let installId = "bourbon.installId"
        static let licenseDisplayName = "bourbon.licenseDisplayName"
        static let licenseStatus = "bourbon.licenseStatus"
        static let licenseMessages = "bourbon.licenseMessages"
        static let licensePermissions = "bourbon.licensePermissions"
        static let licenseWarnings = "bourbon.licenseWarnings"
        static let licenseStrikes = "bourbon.licenseStrikes"
        static let legacyLicenseMigrationAttempted = "bourbon.legacyLicenseMigrationAttempted"
    }

    static func save(_ record: BourbonLicenseRecord) throws {
        savePublicMetadata(record)
        try updateLicenseToken(record.licenseToken)
    }

    static func currentLicense() -> BourbonLicenseRecord? {
        if let record = publicMetadataRecord() {
            return record
        }

        return migrateLegacyLicenseRecordIfNeeded()
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

    static func readLicenseToken() -> String? {
        guard let data = data(account: licenseTokenAccount, logDescription: "license token"),
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }

        print("License token found in Keychain")
        return token
    }

    static func saveLicenseTokenIfMissing(_ token: String) throws {
        guard !token.isEmpty else { return }

        do {
            try add(Data(token.utf8), account: licenseTokenAccount)
            print("License token missing, creating new token")
        } catch LicenseActivationError.keychain(let status) where status == errSecDuplicateItem {
            print("License token found in Keychain")
            return
        }
    }

    static func updateLicenseToken(_ token: String) throws {
        guard !token.isEmpty else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: licenseTokenAccount
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            print("License token updated")
        } else if status == errSecItemNotFound {
            print("License token missing, creating new token")
            try add(Data(token.utf8), account: licenseTokenAccount)
        } else {
            print("License token update failed: \(status)")
            throw LicenseActivationError.keychain(status)
        }
    }

    static func deleteLicenseToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: licenseTokenAccount
        ]

        SecItemDelete(query as CFDictionary)
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

    private static func publicMetadataRecord() -> BourbonLicenseRecord? {
        guard let publicLicenseId = defaults.string(forKey: DefaultsKey.publicLicenseId),
              !publicLicenseId.isEmpty else {
            return nil
        }

        return BourbonLicenseRecord(
            publicLicenseId: publicLicenseId,
            licenseToken: "",
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

    private static func migrateLegacyLicenseRecordIfNeeded() -> BourbonLicenseRecord? {
        guard !defaults.bool(forKey: DefaultsKey.legacyLicenseMigrationAttempted) else {
            return nil
        }

        defaults.set(true, forKey: DefaultsKey.legacyLicenseMigrationAttempted)

        guard let data = data(account: legacyLicenseAccount, logDescription: "legacy license record"),
              let record = try? JSONDecoder().decode(BourbonLicenseRecord.self, from: data) else {
            return nil
        }

        savePublicMetadata(record)

        do {
            try saveLicenseTokenIfMissing(record.licenseToken)
            delete(account: legacyLicenseAccount)
        } catch {
            print("License token migration failed")
        }

        return publicMetadataRecord()
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

    private static func data(account: String, logDescription: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        let messageSubject = logDescription == "license token" ? "License token" : logDescription
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            print("\(messageSubject) missing in Keychain")
            return nil
        default:
            print("\(messageSubject) read failed: \(status)")
            return nil
        }
    }

    private static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
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
    case keychain(OSStatus)
}

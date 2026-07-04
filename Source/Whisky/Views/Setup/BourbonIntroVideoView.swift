import AVKit
import Security
import SwiftUI

// swiftlint:disable file_length

struct BourbonIntroVideoView: View {
    let buttonTitle: String
    let startReturningUserUpdateCheck: () -> Void
    let onFinished: () -> Void

    @State private var player: AVPlayer?
    @State private var showButton = false
    @State private var playbackObserver: NSObjectProtocol?
    @State private var licenseGate: IntroLicenseGate = .idle
    @State private var finishPendingAfterValidation = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
            Color.black.ignoresSafeArea()

                ZStack(alignment: .bottom) {
                    if let player {
                        PlayerContainerView(player: player)
                            .frame(width: introPanelSide(proxy), height: introPanelSide(proxy))
                            .clipped()
                    }

                    Button(buttonTitle) {
                        finishIntro()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.32), in: Capsule())
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(.white)
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.38), lineWidth: 1)
                    )
                    .controlSize(.large)
                    .padding(.bottom, 8)
                    .opacity(showButton ? 1 : 0)
                    .allowsHitTesting(showButton)
                    .animation(.easeOut(duration: 0.6), value: showButton)
                }
                .frame(width: introPanelSide(proxy), height: introPanelSide(proxy))
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(.white.opacity(0.12))
                        }
                )
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.32), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.82), radius: 54, y: 38)
                .shadow(color: .white.opacity(0.08), radius: 18, y: -10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                licenseGateOverlay
            }
        }
        .onAppear {
            startLicenseValidation()
            guard player == nil else { return }

            guard let url = Bundle.main.url(forResource: "BourbonIntro", withExtension: "mov") else {
                finishIntro()
                return
            }

            let player = AVPlayer(url: url)
            self.player = player
            player.play()
            startReturningUserUpdateCheck()

            if let duration = player.currentItem?.asset.duration.seconds,
               duration.isFinite,
               duration > 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + duration - 3.0) {
                    showButton = true
                }
            } else {
                playbackObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: player.currentItem,
                    queue: .main
                ) { _ in
                    Task { @MainActor in
                        showButton = true
                    }
                }
            }
        }
        .onDisappear {
            cleanupPlayer()
        }
    }

    private func introPanelSide(_ proxy: GeometryProxy) -> CGFloat {
        min(proxy.size.width * 0.74, proxy.size.height * 0.74, 760)
    }

    @ViewBuilder
    private var licenseGateOverlay: some View {
        switch licenseGate {
        case .blocked(let result):
            LicenseBlockingView(
                result: result,
                onTryAgain: retryLicenseValidation,
                onAppeal: {
                    try await BourbonLicenseAPI.submitAppeal(for: result)
                }
            )
        case .unavailable(let message):
            LicenseUnavailableView(
                message: message,
                onTryAgain: retryLicenseValidation,
                onContinueOffline: continueOffline
            )
        case .checkingAfterFinish:
            checkingLicenseView
        case .idle, .checking, .valid, .skipped:
            EmptyView()
        }
    }

    private var checkingLicenseView: some View {
        BourbonBackground {
            BourbonGlassCard(maxWidth: 420) {
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Checking your license…")
                        .font(.title2.bold())
                    Text("This usually only takes a moment.")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
            }
        }
        .transition(.opacity)
    }

    private func finishIntro() {
        switch licenseGate {
        case .valid, .skipped:
            completeIntro()
        case .blocked:
            player?.pause()
        case .unavailable:
            player?.pause()
        case .idle, .checking, .checkingAfterFinish:
            player?.pause()
            finishPendingAfterValidation = true
            licenseGate = .checkingAfterFinish
        }
    }

    private func completeIntro() {
        cleanupPlayer()
        onFinished()
    }

    private func startLicenseValidation() {
        switch licenseGate {
        case .idle:
            break
        case .checking, .checkingAfterFinish, .valid, .skipped, .blocked, .unavailable:
            return
        }

        licenseGate = .checking
        print("Starting license validation")

        Task {
            do {
                guard let result = try await BourbonLicenseAPI.validateCurrentLicense() else {
                    print("License validation succeeded")
                    await MainActor.run {
                        licenseGate = .skipped
                        if finishPendingAfterValidation {
                            completeIntro()
                        }
                    }
                    return
                }

                await MainActor.run {
                    if result.isValid && result.status == .valid {
                        print("License validation succeeded")
                        licenseGate = .valid
                        if finishPendingAfterValidation {
                            completeIntro()
                        }
                    } else {
                        print("License validation failed with status: \(result.status.rawValue)")
                        player?.pause()
                        licenseGate = .blocked(result)
                    }
                }
            } catch {
                print("License validation unavailable")
                await MainActor.run {
                    player?.pause()
                    licenseGate = .unavailable(
                        "Bourbon could not reach the license service. " +
                        "You can try again or continue in limited offline mode for now."
                    )
                }
            }
        }
    }

    private func retryLicenseValidation() {
        finishPendingAfterValidation = false
        licenseGate = .idle
        player?.play()
        startLicenseValidation()
    }

    private func continueOffline() {
        print("License validation unavailable")
        completeIntro()
    }

    private func cleanupPlayer() {
        if let playbackObserver {
            NotificationCenter.default.removeObserver(playbackObserver)
            self.playbackObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
}

private enum IntroLicenseGate {
    case idle
    case checking
    case checkingAfterFinish
    case valid
    case skipped
    case blocked(LicenseValidationResult)
    case unavailable(String)
}

private struct LicenseBlockingView: View {
    let result: LicenseValidationResult
    let onTryAgain: () -> Void
    let onAppeal: () async throws -> Void
    @State private var isAppealing = false
    @State private var appealSubmitted = false
    @State private var appealFailed = false

    var body: some View {
        BourbonBackground {
            BourbonGlassCard(maxWidth: 500) {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(BourbonStyle.amber)

                    Text(result.title)
                        .font(.largeTitle.bold())

                    Text(result.reason ?? fallbackReason)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if let deletionScheduledAt = result.deletionScheduledAt {
                        Text(
                            "Deletion scheduled: " +
                            deletionScheduledAt.formatted(date: .abbreviated, time: .shortened)
                        )
                            .font(.caption)
                            .foregroundStyle(BourbonStyle.amber)
                    }

                    if appealSubmitted {
                        Text("Appeal submitted for review.")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if appealFailed {
                        Text("Bourbon could not submit the appeal. Try again later.")
                            .font(.caption)
                            .foregroundStyle(BourbonStyle.amber)
                    }

                    HStack {
                        Button("Try Again") {
                            onTryAgain()
                        }
                        .buttonStyle(BourbonSecondaryButtonStyle())
                        .disabled(isAppealing)

                        if result.appealAllowed {
                            Button {
                                submitAppeal()
                            } label: {
                                if isAppealing {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text("Appeal")
                                }
                            }
                            .buttonStyle(BourbonPrimaryButtonStyle())
                            .disabled(isAppealing || appealSubmitted)
                        }
                    }
                }
                .multilineTextAlignment(.center)
            }
        }
        .transition(.opacity)
    }

    private var fallbackReason: String {
        "This license cannot continue into Bourbon right now."
    }

    private func submitAppeal() {
        isAppealing = true
        appealFailed = false

        Task {
            do {
                try await onAppeal()
                await MainActor.run {
                    isAppealing = false
                    appealSubmitted = true
                }
            } catch {
                await MainActor.run {
                    isAppealing = false
                    appealFailed = true
                }
            }
        }
    }
}

private struct LicenseUnavailableView: View {
    let message: String
    let onTryAgain: () -> Void
    let onContinueOffline: () -> Void

    var body: some View {
        BourbonBackground {
            BourbonGlassCard(maxWidth: 500) {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(BourbonStyle.amber)

                    Text("License check unavailable")
                        .font(.largeTitle.bold())

                    Text(message)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button("Try Again") {
                            onTryAgain()
                        }
                        .buttonStyle(BourbonSecondaryButtonStyle())

                        Button("Continue Offline") {
                            onContinueOffline()
                        }
                        .buttonStyle(BourbonPrimaryButtonStyle())
                    }
                }
                .multilineTextAlignment(.center)
            }
        }
        .transition(.opacity)
    }
}

struct AdminUnlockView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var licenseID = ""
    @State private var password = ""
    @State private var isUnlocking = false
    @State private var unlockFailed = false
    @State private var adminSession = AdminSessionStore.currentSession()

    var body: some View {
        BourbonPanelBackdrop {
            if let adminSession {
                BourbonFloatingPanel(maxWidth: 700) {
                    AdminLicenseModerationView(session: adminSession) {
                        dismiss()
                    }
                }
            } else {
                BourbonFloatingPanel(maxWidth: 420) {
                    unlockContent
                }
            }
        }
        .frame(width: adminSession == nil ? 520 : 720, height: adminSession == nil ? 360 : 640)
    }

    private var unlockContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Unlock Access")
                    .font(.title.bold())
                Text("Enter your credentials to continue.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                TextField("License ID", text: $licenseID)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isUnlocking)

                SecureField("Admin password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isUnlocking)
            }

            if unlockFailed {
                Text("Could not unlock admin access.")
                    .font(.caption)
                    .foregroundStyle(BourbonStyle.amber)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(BourbonSecondaryButtonStyle())
                .disabled(isUnlocking)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    unlock()
                } label: {
                    if isUnlocking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Unlock")
                    }
                }
                .buttonStyle(BourbonPrimaryButtonStyle())
                .disabled(isUnlocking || licenseID.isEmpty || password.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func unlock() {
        isUnlocking = true
        unlockFailed = false

        Task {
            do {
                let session = try await AdminSessionAPI.createSession(
                    licenseID: licenseID,
                    password: password
                )
                try AdminSessionStore.save(session)
                await MainActor.run {
                    adminSession = session
                    isUnlocking = false
                }
            } catch {
                await MainActor.run {
                    isUnlocking = false
                    unlockFailed = true
                }
            }
        }
    }
}

struct AdminLicenseModerationView: View {
    let session: AdminSession
    let onDone: () -> Void
    @State private var lookupLicenseID = ""
    @State private var licenseSummary: AdminLicenseSummary?
    @State private var selectedAction: AdminLicenseAction = .select
    @State private var appealOption: AdminAppealOption = .select
    @State private var reason = ""
    @State private var isLookingUp = false
    @State private var isApplying = false
    @State private var message: String?
    @State private var showConfirmation = false

    var body: some View {
        BourbonGlassCard(maxWidth: 640) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    lookupSection
                    licenseSummarySection
                    moderationSection
                    footer
                }
                .padding(.vertical, 4)
            }
        }
        .alert("Apply license action?", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Apply Action", role: .destructive) {
                applyModerationAction()
            }
        } message: {
            Text(confirmationSummary)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("License Moderation")
                .font(.title.bold())
            Text("Search a license, choose an action, enter a reason, and choose appeal availability.")
                .foregroundStyle(.secondary)
        }
    }

    private var lookupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Find License")
                .font(.headline)

            HStack {
                TextField("BRBN-00000001", text: $lookupLicenseID)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isLookingUp || isApplying)

                Button {
                    lookupLicense()
                } label: {
                    if isLookingUp {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Search")
                    }
                }
                .buttonStyle(BourbonSecondaryButtonStyle())
                .disabled(lookupLicenseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLookingUp)
            }
        }
    }

    @ViewBuilder
    private var licenseSummarySection: some View {
        if let licenseSummary {
            VStack(alignment: .leading, spacing: 10) {
                Text("License")
                    .font(.headline)
                infoRow("License ID", licenseSummary.licenseId)
                infoRow("Status", licenseSummary.status.rawValue.capitalized)
                if let reason = licenseSummary.reason, !reason.isEmpty {
                    infoRow("Reason", reason)
                }
                if let deletionScheduledAt = licenseSummary.deletionScheduledAt {
                    infoRow("Deletion scheduled", deletionScheduledAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .padding(14)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var moderationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Action")
                .font(.headline)

            Picker("Action", selection: $selectedAction) {
                ForEach(AdminLicenseAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            }

            TextField("Reason", text: $reason, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(4, reservesSpace: true)

            Picker("Appeal", selection: $appealOption) {
                ForEach(AdminAppealOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(BourbonStyle.amber)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Done") {
                onDone()
            }
            .buttonStyle(BourbonSecondaryButtonStyle())
            .disabled(isApplying)

            Spacer()

            Button("Apply Action") {
                showConfirmation = true
            }
            .buttonStyle(BourbonPrimaryButtonStyle())
            .disabled(!canApply || isApplying)
        }
    }

    private var canApply: Bool {
        licenseSummary != nil &&
        selectedAction != .select &&
        appealOption != .select &&
        !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var confirmationSummary: String {
        let licenseId = licenseSummary?.licenseId ?? lookupLicenseID
        return "\(selectedAction.title) for \(licenseId).\n\nReason: \(reason)"
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func lookupLicense() {
        isLookingUp = true
        message = nil

        Task {
            do {
                let summary = try await AdminLicenseModerationAPI.lookupLicense(
                    licenseID: lookupLicenseID,
                    session: session
                )
                await MainActor.run {
                    licenseSummary = summary
                    isLookingUp = false
                }
            } catch {
                await MainActor.run {
                    isLookingUp = false
                    message = "Could not load that license."
                }
            }
        }
    }

    private func applyModerationAction() {
        guard let licenseSummary,
              let appealAllowed = appealOption.appealAllowed else {
            return
        }

        isApplying = true
        message = nil

        let deletionScheduledAt = selectedAction == .delete && !appealAllowed
            ? Calendar.current.date(byAdding: .hour, value: 72, to: Date())
            : nil
        let command = AdminLicenseModerationCommand(
            licenseID: licenseSummary.licenseId,
            action: selectedAction,
            reason: reason,
            appealAllowed: appealAllowed,
            deletionScheduledAt: deletionScheduledAt
        )

        Task {
            do {
                let updated = try await AdminLicenseModerationAPI.applyAction(
                    command: command,
                    session: session
                )
                await MainActor.run {
                    self.licenseSummary = updated
                    isApplying = false
                    message = "Action applied."
                }
            } catch {
                await MainActor.run {
                    isApplying = false
                    message = "Could not apply that action."
                }
            }
        }
    }
}

enum AdminLicenseAction: String, CaseIterable, Identifiable, Codable {
    case select
    case pause
    case delete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select:
            return "Select action"
        case .pause:
            return "Pause license"
        case .delete:
            return "Delete license"
        }
    }

    var resultingStatus: LicenseValidationStatus {
        switch self {
        case .select:
            return .unknown
        case .pause:
            return .paused
        case .delete:
            return .scheduledForDeletion
        }
    }
}

enum AdminAppealOption: String, CaseIterable, Identifiable {
    case select
    case yes
    case denied

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select:
            return "Select option"
        case .yes:
            return "Yes, appeal allowed"
        case .denied:
            return "No, appeal not allowed"
        }
    }

    var appealAllowed: Bool? {
        switch self {
        case .select:
            return nil
        case .yes:
            return true
        case .denied:
            return false
        }
    }
}

struct AdminLicenseModerationCommand {
    let licenseID: String
    let action: AdminLicenseAction
    let reason: String
    let appealAllowed: Bool
    let deletionScheduledAt: Date?
}

struct AdminLicenseSummary: Codable {
    let licenseId: String
    let status: LicenseValidationStatus
    let reason: String?
    let appealAllowed: Bool
    let deletionScheduledAt: Date?
    let updatedAt: Date
}

enum AdminLicenseModerationAPI {
    static func lookupLicense(
        licenseID: String,
        session: AdminSession
    ) async throws -> AdminLicenseSummary {
        if !AdminAPIConfiguration.hasConfiguredBackend {
            return mockSummary(licenseID: licenseID, status: .valid, reason: nil, appealAllowed: false)
        }

        var request = URLRequest(url: AdminAPIConfiguration.licenseLookupURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(AdminLicenseLookupRequest(licenseId: licenseID))

        let (data, response) = try await URLSession(configuration: sessionConfiguration).data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw AdminUnlockError.invalidResponse
        }

        return try decoder.decode(AdminLicenseSummary.self, from: data)
    }

    static func applyAction(
        command: AdminLicenseModerationCommand,
        session: AdminSession
    ) async throws -> AdminLicenseSummary {
        if !AdminAPIConfiguration.hasConfiguredBackend {
            return mockSummary(
                licenseID: command.licenseID,
                status: command.action.resultingStatus,
                reason: command.reason,
                appealAllowed: command.appealAllowed,
                deletionScheduledAt: command.deletionScheduledAt
            )
        }

        var request = URLRequest(url: AdminAPIConfiguration.licenseModerationURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(AdminLicenseModerationRequest(
            licenseId: command.licenseID,
            action: command.action.rawValue,
            reason: command.reason,
            appealAllowed: command.appealAllowed,
            deletionScheduledAt: command.deletionScheduledAt
        ))

        let (data, response) = try await URLSession(configuration: sessionConfiguration).data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw AdminUnlockError.invalidResponse
        }

        return try decoder.decode(AdminLicenseSummary.self, from: data)
    }

    private static var sessionConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        return configuration
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func mockSummary(
        licenseID: String,
        status: LicenseValidationStatus,
        reason: String?,
        appealAllowed: Bool,
        deletionScheduledAt: Date? = nil
    ) -> AdminLicenseSummary {
        // Future backend: replace this local development result with the
        // admin license moderation API once the endpoint is available.
        AdminLicenseSummary(
            licenseId: licenseID,
            status: status,
            reason: reason,
            appealAllowed: appealAllowed,
            deletionScheduledAt: deletionScheduledAt,
            updatedAt: Date()
        )
    }
}

private struct AdminLicenseLookupRequest: Encodable {
    let licenseId: String
}

private struct AdminLicenseModerationRequest: Encodable {
    let licenseId: String
    let action: String
    let reason: String
    let appealAllowed: Bool
    let deletionScheduledAt: Date?
}

struct AdminSession: Codable {
    let token: String
    let expiresAt: Date
}

enum AdminSessionAPI {
    static func createSession(licenseID: String, password: String) async throws -> AdminSession {
        var request = URLRequest(url: AdminAPIConfiguration.sessionURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AdminSessionRequest(licenseId: licenseID, password: password))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw AdminUnlockError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AdminSessionResponse.self, from: data)

        guard decoded.isOK,
              let token = decoded.adminSessionToken,
              let expiresAt = decoded.expiresAt,
              expiresAt > Date() else {
            throw AdminUnlockError.invalidResponse
        }

        return AdminSession(token: token, expiresAt: expiresAt)
    }
}

private struct AdminSessionRequest: Encodable {
    let licenseId: String
    let password: String
}

private struct AdminSessionResponse: Decodable {
    let isOK: Bool
    let adminSessionToken: String?
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case isOK = "ok"
        case adminSessionToken
        case expiresAt
    }
}

enum AdminAPIConfiguration {
    private struct LocalConfig: Decodable {
        let adminAPIBaseURL: String?
    }

    static var sessionURL: URL {
        baseURL.appending(path: "admin/session")
    }

    static var licenseLookupURL: URL {
        baseURL.appending(path: "admin/licenses/lookup")
    }

    static var licenseModerationURL: URL {
        baseURL.appending(path: "admin/licenses/moderate")
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

        guard let url = URL(string: "https://api.bourbon.app") else {
            preconditionFailure("Invalid default Bourbon API URL.")
        }
        return url
    }

    private static var environmentBaseURL: URL? {
        guard let environmentURL = ProcessInfo.processInfo.environment["BOURBON_ADMIN_API_BASE_URL"] else {
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
                  let rawURL = config.adminAPIBaseURL,
                  let url = URL(string: rawURL) else {
                continue
            }
            return url
        }

        return nil
    }
}

enum AdminSessionStore {
    private static let service = "com.unblockerfire.Bourbon.admin-session"
    private static let account = "admin-session-token"

    static func save(_ session: AdminSession) throws {
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AdminUnlockError.keychain(status)
        }
    }

    static func currentSession() -> AdminSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let session = try? JSONDecoder().decode(AdminSession.self, from: data) else {
            return nil
        }

        guard session.expiresAt > Date() else {
            delete()
            return nil
        }

        return session
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum AdminUnlockError: Error {
    case invalidResponse
    case keychain(OSStatus)
}

struct PlayerContainerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
    }
}

import AVFoundation
import AppKit
import QuartzCore
import Security
import SwiftUI
import WhiskyKit

// swiftlint:disable file_length

// swiftlint:disable type_body_length
struct BourbonIntroVideoView: View {
    let buttonTitle: String
    let startReturningUserUpdateCheck: () -> Void
    let onFinished: () -> Void

    @State private var player: AVPlayer?
    @State private var showButton = false
    @State private var licenseGate: IntroLicenseGate = .idle
    @State private var finishPendingAfterValidation = false
    @State private var licenseActivity = BourbonLicenseActivityState()
    @State private var licenseTask: Task<Void, Never>?
    @State private var licenseFailureCode: String?
    @State private var surfaceDiagnosticCode = "surface_pending"
    @State private var surfaceDiagnosticReport = "No window hierarchy has been captured yet."
    @State private var diagnosticCopyConfirmation = false
    @State private var didStartReturningUserUpdateCheck = false
    @State private var playerNotificationTokens: [NSObjectProtocol] = []
    @AppStorage("hasRejectedLicense") private var hasRejectedLicense = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                if licenseGate.mountsIntroSurface {
                    introSurface(proxy: proxy)
                }

                if licenseGate.presentsBlockingOverlay {
                    licenseGateOverlay
                        .background(BourbonSurfaceOwnershipMarker(role: "license_overlay"))
                }

                if isDiagnosticBuild {
                    diagnosticChrome
                }
            }
        }
        .onAppear {
            applyDiagnosticWindowTitle()
            BourbonLicenseDiagnostics.record("license.ui.opened")
            reportResponsive(stage: "opened")
            prepareIntroPlayerIfNeeded()
            startLicenseValidation()
        }
        .onDisappear {
            licenseTask?.cancel()
            licenseTask = nil
            licenseActivity.cancel()
            cleanupPlayer()
        }
        .onChange(of: licenseGate.overlayDiagnosticName) { oldValue, newValue in
            if let oldValue {
                BourbonLicenseDiagnostics.record("license.overlay.dismissed", detail: "kind=\(oldValue)")
                reportSurfaceOwnership(stage: "overlay_dismissed")
            }
            if let newValue {
                BourbonLicenseDiagnostics.record("license.overlay.presented", detail: "kind=\(newValue)")
                cleanupPlayer(reason: "blocking_license_overlay")
                reportSurfaceOwnership(stage: "overlay_presented")
            }
            reportResponsive(stage: "overlay_changed")
        }
    }

    private var isDiagnosticBuild: Bool {
        Bundle.main.bundleIdentifier == BourbonLicenseStoragePolicy.diagnosticBundleIdentifier
    }

    private var diagnosticChrome: some View {
        VStack {
            HStack {
                Text(
                    "Diagnostic \(BourbonBuildDiagnostics.current.gitCommitShort) · " +
                        "PID \(ProcessInfo.processInfo.processIdentifier)"
                )
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.62), in: Capsule())

                Spacer()

                Button(diagnosticCopyConfirmation ? "UI Report Copied" : "Copy UI Report") {
                    copySurfaceDiagnostics()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)

            Spacer()

            HStack {
                Text(surfaceDiagnosticCode)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.62), in: Capsule())
                Spacer()
            }
            .padding(12)
        }
        .zIndex(100)
    }

    private func applyDiagnosticWindowTitle() {
        guard isDiagnosticBuild else { return }
        Task { @MainActor in
            await Task.yield()
            let title = "Bourbon Diagnostic · \(BourbonBuildDiagnostics.current.gitCommitShort)"
            for window in NSApp.windows where window.isVisible {
                window.title = title
            }
        }
    }

    private func introPanelSide(_ proxy: GeometryProxy) -> CGFloat {
        min(proxy.size.width * 0.74, proxy.size.height * 0.74, 760)
    }

    private func introSurface(proxy: GeometryProxy) -> some View {
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
            .background(BourbonStyle.panelStrong, in: Capsule())
            .foregroundStyle(BourbonStyle.primaryText)
            .overlay(
                Capsule()
                    .stroke(BourbonStyle.cardStroke, lineWidth: 1)
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
                .fill(BourbonStyle.panel)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(BourbonStyle.cardStroke, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.82), radius: 54, y: 38)
        .background(BourbonSurfaceOwnershipMarker(role: "intro_surface"))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var licenseGateOverlay: some View {
        switch licenseGate {
        case .warning(let result):
            LicenseWarningView(result: result, onAcknowledge: acknowledgeWarning)
        case .blocked(let result):
            LicenseBlockingView(
                result: result,
                onTryAgain: retryLicenseValidation,
                onAppeal: {
                    try await BourbonLicenseAPI.submitAppeal(for: result)
                }
            )
        case .unavailable(let message, let allowsFreshActivation):
            LicenseUnavailableView(
                message: message,
                onTryAgain: retryLicenseValidation,
                onRecover: recoverLicense,
                onSupport: openSupport,
                onStartFreshActivation: startFreshActivation,
                allowsRecovery: true,
                allowsFreshActivation: allowsFreshActivation,
                diagnosticCode: licenseFailureCode,
                surfaceDiagnosticCode: surfaceDiagnosticCode,
                onCopySurfaceDiagnostics: copySurfaceDiagnostics
            )
        case .checking, .checkingAfterFinish:
            checkingLicenseView
        case .recovering:
            recoveringLicenseView
        case .idle, .valid:
            EmptyView()
        }
    }

    private var checkingLicenseView: some View {
        BourbonBackground {
            BourbonGlassCard(maxWidth: 420) {
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(BourbonStyle.amber)
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

    private var recoveringLicenseView: some View {
        BourbonBackground {
            BourbonGlassCard(maxWidth: 420) {
                VStack(spacing: 14) {
                    Image(systemName: "key.horizontal")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(BourbonStyle.amber)
                    Text("Restoring your license…")
                        .font(.title2.bold())
                    Text("Bourbon will return to the license screen if restoration cannot complete.")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
            }
        }
        .transition(.opacity)
    }

    private func finishIntro() {
        switch licenseGate {
        case .valid:
            completeIntro()
        case .warning:
            player?.pause()
        case .blocked:
            player?.pause()
        case .unavailable:
            player?.pause()
        case .idle, .checking, .checkingAfterFinish, .recovering:
            player?.pause()
            finishPendingAfterValidation = true
            licenseGate = .checkingAfterFinish
        }
    }

    private func completeIntro() {
        cleanupPlayer()
        onFinished()
    }

    private func startFreshActivation() {
        licenseTask?.cancel()
        licenseTask = nil
        licenseActivity.cancel()
        cleanupPlayer()
        onFinished()
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func startLicenseValidation() {
        switch licenseGate {
        case .idle:
            break
        case .checking, .checkingAfterFinish, .recovering, .valid, .warning, .blocked, .unavailable:
            return
        }

        licenseGate = .checking
        licenseFailureCode = nil
        licenseTask?.cancel()
        let requestID = licenseActivity.begin()
        BourbonLicenseDiagnostics.record("license.validation.started")

        licenseTask = Task {
            do {
                let result = try await BourbonLicenseAPI.validateCurrentLicense()
                await MainActor.run {
                    guard licenseActivity.finish(requestID) else { return }
                    BourbonLicenseDiagnostics.record(
                        "license.validation.completed",
                        detail: "status=\(result.status.rawValue) allowed=\(result.allowed)"
                    )
                    if result.isValid && result.allowed && result.status == .valid {
                        hasRejectedLicense = false
                        if result.warnings.isEmpty {
                            licenseGate = .valid
                            if finishPendingAfterValidation {
                                completeIntro()
                            } else {
                                prepareIntroPlayerIfNeeded()
                            }
                        } else {
                            player?.pause()
                            licenseGate = .warning(result)
                        }
                    } else {
                        hasRejectedLicense = true
                        player?.pause()
                        licenseGate = .blocked(result)
                    }
                    reportResponsive(stage: "validation_completed")
                }
            } catch LicenseActivationError.missingToken {
                BourbonLicenseDiagnostics.record("license.validation.failed", detail: "code=missing_token")
                await MainActor.run {
                    guard licenseActivity.finish(requestID) else { return }
                    licenseFailureCode = "missing_token"
                    player?.pause()
                    licenseGate = .unavailable(
                        "Bourbon could not find a usable license on this Mac. " +
                        "Restore a saved key or start a fresh license activation.",
                        true
                    )
                    reportResponsive(stage: "validation_failed")
                }
            } catch LicenseActivationError.licenseReset {
                BourbonLicenseDiagnostics.record("license.validation.failed", detail: "code=license_reset")
                await MainActor.run {
                    guard licenseActivity.finish(requestID) else { return }
                    licenseFailureCode = "license_reset"
                    player?.pause()
                    licenseGate = .unavailable(
                        "This installation used an older Bourbon license that is no longer available. " +
                        "Start a fresh license activation to continue.",
                        true
                    )
                    reportResponsive(stage: "validation_failed")
                }
            } catch LicenseActivationError.blocked(let result) {
                BourbonLicenseDiagnostics.record(
                    "license.validation.failed",
                    detail: "code=blocked status=\(result.status.rawValue)"
                )
                await MainActor.run {
                    guard licenseActivity.finish(requestID) else { return }
                    licenseFailureCode = "blocked_\(result.status.rawValue)"
                    player?.pause()
                    licenseGate = .blocked(result)
                    reportResponsive(stage: "validation_failed")
                }
            } catch LicenseActivationError.keychain(let status) {
                BourbonLicenseDiagnostics.record(
                    "license.validation.failed",
                    detail: "code=keychain status=\(status)"
                )
                await MainActor.run {
                    guard licenseActivity.finish(requestID) else { return }
                    licenseFailureCode = "keychain_\(status)"
                    player?.pause()
                    licenseGate = .unavailable(
                        "Bourbon Diagnostic found license metadata, but macOS did not allow non-interactive " +
                        "access to its secure token. Restore a saved key or try again after opening " +
                        "production Bourbon.",
                        false
                    )
                    reportResponsive(stage: "validation_failed")
                }
            } catch let failure as BourbonLicenseServiceFailure {
                BourbonLicenseDiagnostics.record(
                    "license.validation.failed",
                    detail: "code=\(failure.diagnosticCode)"
                )
                await MainActor.run {
                    guard licenseActivity.finish(requestID) else { return }
                    licenseFailureCode = failure.diagnosticCode
                    licenseGate = .unavailable(failure.userMessage, false)
                    reportResponsive(stage: "validation_failed_\(failure.diagnosticCode)")
                }
            } catch is CancellationError {
                BourbonLicenseDiagnostics.record("license.validation.failed", detail: "code=cancelled")
                await MainActor.run {
                    guard licenseActivity.finish(requestID) else { return }
                    licenseFailureCode = "cancelled"
                    licenseGate = .unavailable(
                        "License validation was cancelled. Try again when you are ready.",
                        false
                    )
                    reportResponsive(stage: "validation_cancelled")
                }
            } catch {
                BourbonLicenseDiagnostics.record("license.validation.failed", detail: "code=unexpected")
                await MainActor.run {
                    guard licenseActivity.finish(requestID) else { return }
                    licenseFailureCode = "unexpected"
                    player?.pause()
                    licenseGate = .unavailable(
                        "Bourbon could not complete license validation. " +
                        "Select Try Again and send the diagnostic code if it continues.",
                        false
                    )
                    reportResponsive(stage: "validation_failed")
                }
            }
        }
    }

    private func retryLicenseValidation() {
        licenseTask?.cancel()
        licenseTask = nil
        licenseActivity.cancel()
        finishPendingAfterValidation = false
        licenseGate = .idle
        startLicenseValidation()
    }

    private func acknowledgeWarning() {
        licenseGate = .valid
        if finishPendingAfterValidation {
            completeIntro()
        } else {
            prepareIntroPlayerIfNeeded()
        }
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func recoverLicense(_ key: String) {
        player?.pause()
        licenseTask?.cancel()
        let requestID = licenseActivity.begin()
        licenseGate = .recovering
        reportResponsive(stage: "recovery_started")
        licenseTask = Task {
            do {
                print("License recovery request started")
                let outcome = try await BourbonLicenseAPI.recoverLicense(key: key)
                try await LicenseKeychainStore.saveAsync(outcome.record)
                print("License recovery credential saved")
                await MainActor.run {
                    guard licenseActivity.finish(requestID) else { return }
                    if outcome.validation.warnings.isEmpty {
                        hasRejectedLicense = false
                        licenseGate = .valid
                        if finishPendingAfterValidation {
                            completeIntro()
                        } else {
                            prepareIntroPlayerIfNeeded()
                        }
                    } else {
                        licenseGate = .warning(outcome.validation)
                    }
                }
            } catch LicenseActivationError.blocked(let result) {
                await MainActor.run {
                    guard licenseActivity.finish(requestID) else { return }
                    licenseGate = .blocked(result)
                }
            } catch LicenseActivationError.keychain {
                await MainActor.run {
                    guard licenseActivity.finish(requestID) else { return }
                    licenseGate = .unavailable(
                        "Bourbon restored the license, but could not save it securely on this Mac. " +
                        "Please try again.",
                        false
                    )
                }
            } catch LicenseActivationError.invalidLicense {
                await MainActor.run {
                    guard licenseActivity.finish(requestID) else { return }
                    licenseGate = .unavailable(
                        "That license key is invalid or no longer available. " +
                        "Please check the key and try again.",
                        false
                    )
                }
            } catch LicenseActivationError.rateLimited {
                await MainActor.run {
                    guard licenseActivity.finish(requestID) else { return }
                    licenseGate = .unavailable(
                        "Too many recovery attempts were made. Please wait a moment and try again.",
                        false
                    )
                }
            } catch LicenseActivationError.service {
                await MainActor.run {
                    guard licenseActivity.finish(requestID) else { return }
                    licenseGate = .unavailable(
                        "Bourbon couldn’t reach the licensing service. Please try again.",
                        false
                    )
                }
            } catch LicenseActivationError.network {
                await MainActor.run {
                    guard licenseActivity.finish(requestID) else { return }
                    licenseGate = .unavailable(
                        "Bourbon couldn’t contact the licensing service. Check your connection and try again.",
                        false
                    )
                }
            } catch LicenseActivationError.invalidResponse {
                await MainActor.run {
                    guard licenseActivity.finish(requestID) else { return }
                    licenseGate = .unavailable(
                        "Bourbon received an invalid response from the licensing service. Please try again.",
                        false
                    )
                }
            } catch {
                await MainActor.run {
                    guard licenseActivity.finish(requestID) else { return }
                    licenseGate = .unavailable(
                        "Bourbon could not complete license recovery. Please try again. " +
                        "If the problem continues, contact Bourbon support.",
                        false
                    )
                }
            }
        }
    }

    private func openSupport() {
        guard let url = URL(string: BourbonSupport.discordURL) else { return }
        NSWorkspace.shared.open(url)
    }

    private func prepareIntroPlayerIfNeeded() {
        showButton = true
        guard player == nil else {
            player?.play()
            reportSurfaceOwnership(stage: "intro_ready")
            return
        }
        guard let url = Bundle.main.url(forResource: "BourbonIntro", withExtension: "mov") else {
            BourbonLicenseDiagnostics.record("license.player.unavailable", detail: "reason=resource_missing")
            reportSurfaceOwnership(stage: "intro_ready_without_player")
            return
        }

        let player = AVPlayer(url: url)
        self.player = player
        BourbonLicenseDiagnostics.record("intro.video.asset.loaded", detail: "resource=BourbonIntro.mov")
        let center = NotificationCenter.default
        playerNotificationTokens = [
            center.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
            ) { _ in
                BourbonLicenseDiagnostics.record("intro.video.playback.completed")
            },
            center.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime, object: player.currentItem, queue: .main
            ) { notification in
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                let errorDescription = error?.localizedDescription ?? "unknown"
                BourbonLicenseDiagnostics.record(
                    "intro.video.playback.failed",
                    detail: "error=\(errorDescription)"
                )
            }
        ]
        player.play()
        BourbonLicenseDiagnostics.record("intro.video.player.created")
        BourbonLicenseDiagnostics.record("intro.video.playback.started")
        reportSurfaceOwnership(stage: "intro_ready")
        if !didStartReturningUserUpdateCheck {
            didStartReturningUserUpdateCheck = true
            startReturningUserUpdateCheck()
        }
    }

    private func cleanupPlayer(reason: String = "view_disappeared") {
        let hadPlayerSurface = player != nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        playerNotificationTokens.forEach(NotificationCenter.default.removeObserver)
        playerNotificationTokens.removeAll()
        showButton = false
        if hadPlayerSurface {
            BourbonLicenseDiagnostics.record("license.player.destroyed", detail: "reason=\(reason)")
        }
    }

    private func reportSurfaceOwnership(stage: String) {
        Task { @MainActor in
            await Task.yield()
            let snapshot = BourbonWindowHierarchyDiagnostics.capture(stage: stage)
            surfaceDiagnosticCode = snapshot.code
            surfaceDiagnosticReport = snapshot.report
            BourbonLicenseDiagnostics.record(
                "license.ui.surface.audit",
                detail: "stage=\(stage) code=\(surfaceDiagnosticCode)"
            )
        }
    }

    private func copySurfaceDiagnostics() {
        let snapshot = BourbonWindowHierarchyDiagnostics.copyCurrentReport(stage: "copy_ui_report")
        surfaceDiagnosticCode = snapshot.code
        surfaceDiagnosticReport = snapshot.report
        diagnosticCopyConfirmation = true
    }

    private func reportResponsive(stage: String) {
        Task { @MainActor in
            await Task.yield()
            BourbonLicenseDiagnostics.record("license.ui.responsive", detail: "stage=\(stage)")
        }
    }
}

// swiftlint:enable type_body_length

private enum IntroLicenseGate {
    case idle
    case checking
    case checkingAfterFinish
    case recovering
    case valid
    case warning(LicenseValidationResult)
    case blocked(LicenseValidationResult)
    case unavailable(String, Bool)

    var presentsBlockingOverlay: Bool {
        overlayDiagnosticName != nil
    }

    var mountsIntroSurface: Bool {
        switch self {
        case .idle, .checking, .checkingAfterFinish, .valid:
            true
        case .recovering, .warning, .blocked, .unavailable:
            false
        }
    }

    var overlayDiagnosticName: String? {
        switch self {
        case .checking, .checkingAfterFinish:
            return "validation"
        case .recovering:
            return "recovery"
        case .warning:
            return "warning"
        case .blocked:
            return "blocked"
        case .unavailable:
            return "unavailable"
        case .idle, .valid:
            return nil
        }
    }
}

private struct LicenseWarningView: View {
    let result: LicenseValidationResult
    let onAcknowledge: () -> Void

    var body: some View {
        BourbonBackground {
            BourbonGlassCard(maxWidth: 500) {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(BourbonStyle.amber)

                    Text("License notice")
                        .font(.largeTitle.bold())

                    ForEach(result.warnings, id: \.self) { warning in
                        Text(warning)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button("Acknowledge and Continue") {
                        onAcknowledge()
                    }
                    .buttonStyle(BourbonPrimaryButtonStyle())
                }
                .multilineTextAlignment(.center)
            }
        }
        .transition(.opacity)
    }
}

private struct LicenseBlockingView: View {
    @Environment(\.openURL) private var openURL
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

                    Text(displayReason)
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

                    if result.revoked {
                        Button("Open Discord Support") {
                            if let url = URL(string: BourbonSupport.discordURL) {
                                openURL(url)
                            }
                        }
                        .buttonStyle(BourbonSecondaryButtonStyle())
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

    private var displayReason: String {
        if result.revoked {
            return "Your license has been revoked. Please open a support ticket in Discord."
        }
        return result.reason ?? fallbackReason
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
    let onRecover: (String) -> Void
    let onSupport: () -> Void
    let onStartFreshActivation: () -> Void
    let allowsRecovery: Bool
    let allowsFreshActivation: Bool
    let diagnosticCode: String?
    let surfaceDiagnosticCode: String
    let onCopySurfaceDiagnostics: () -> Void
    @State private var licenseKey = ""
    @State private var showingKeyInput = false
    @State private var showingSupport = false

    var body: some View {
        BourbonBackground {
            BourbonGlassCard(maxWidth: 500) {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(BourbonStyle.amber)

                    Text("License unavailable")
                        .font(.largeTitle.bold())

                    Text(message)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if showingSupport {
                        Text(
                            "For security, Bourbon cannot automatically restore a lost license " +
                            "without the license key. Please open a support ticket in Discord " +
                            "so we can help verify and recover your license."
                        )
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("Open Discord Support") { onSupport() }
                            .buttonStyle(BourbonPrimaryButtonStyle())
                        Button("Back") { showingSupport = false }
                            .buttonStyle(BourbonSecondaryButtonStyle())
                    } else if showingKeyInput {
                        TextField("Paste your Bourbon license key", text: $licenseKey)
                            .textFieldStyle(BourbonTextFieldStyle())
                            .textSelection(.enabled)

                        HStack {
                            Button("Back") { showingKeyInput = false }
                                .buttonStyle(BourbonSecondaryButtonStyle())
                            Button("Restore License") {
                                onRecover(licenseKey.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            .buttonStyle(BourbonPrimaryButtonStyle())
                            .disabled(licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    } else {
                        if allowsRecovery {
                            Button("I Have a License Key") { showingKeyInput = true }
                                .buttonStyle(BourbonPrimaryButtonStyle())
                            Button("I Don't Have My License Key") { showingSupport = true }
                                .buttonStyle(BourbonSecondaryButtonStyle())
                        }
                        if allowsFreshActivation {
                            Button("Start Fresh License Activation") { onStartFreshActivation() }
                                .buttonStyle(BourbonPrimaryButtonStyle())
                        }
                        Button("Try Again") { onTryAgain() }
                            .buttonStyle(BourbonSecondaryButtonStyle())
                    }

                    if let diagnosticCode {
                        Text("Diagnostic code: \(diagnosticCode) · \(surfaceDiagnosticCode)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button("Copy UI Diagnostics") { onCopySurfaceDiagnostics() }
                            .buttonStyle(BourbonSecondaryButtonStyle())
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
                    .textFieldStyle(BourbonTextFieldStyle())
                    .disabled(isUnlocking)

                SecureField("Admin password", text: $password)
                    .textFieldStyle(BourbonTextFieldStyle())
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
                    .textFieldStyle(BourbonTextFieldStyle())
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
                .textFieldStyle(BourbonTextFieldStyle())
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

        guard let url = URL(string: "https://api.getbourbon.app") else {
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

private struct PlayerContainerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> BourbonPlayerSurfaceNSView {
        let view = BourbonPlayerSurfaceNSView()
        view.playerLayer.player = player
        BourbonLicenseDiagnostics.record("license.player.surface.created", detail: "kind=avplayerlayer")
        return view
    }

    func updateNSView(_ nsView: BourbonPlayerSurfaceNSView, context: Context) {
        nsView.playerLayer.player = player
    }

    static func dismantleNSView(_ nsView: BourbonPlayerSurfaceNSView, coordinator: ()) {
        nsView.playerLayer.player?.pause()
        nsView.playerLayer.player = nil
        BourbonLicenseDiagnostics.record("license.player.surface.destroyed", detail: "kind=avplayerlayer")
    }
}

private final class BourbonPlayerSurfaceNSView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier("bourbon.surface.video_layer")
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct BourbonSurfaceOwnershipMarker: NSViewRepresentable {
    let role: String

    func makeNSView(context: Context) -> BourbonSurfaceMarkerNSView {
        BourbonSurfaceMarkerNSView(role: role)
    }

    func updateNSView(_ nsView: BourbonSurfaceMarkerNSView, context: Context) {
        nsView.role = role
    }
}

private final class BourbonSurfaceMarkerNSView: NSView {
    var role: String {
        didSet {
            identifier = NSUserInterfaceItemIdentifier("bourbon.surface.\(role)")
        }
    }

    init(role: String) {
        self.role = role
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("bourbon.surface.\(role)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override var acceptsFirstResponder: Bool {
        false
    }
}

@MainActor
enum BourbonWindowHierarchyDiagnostics {
    struct Snapshot {
        let code: String
        let report: String
    }

    private struct CaptureState {
        var lines: [String]
        var viewCount = 0
        var playerViewCount = 0
        var introMarkerCount = 0
        var licenseMarkerCount = 0
        var compositorWindowCount = 0
    }

    private static let maximumViews = 256

    static func capture(stage: String) -> Snapshot {
        let allApplicationWindows = NSApp.windows
        let windows = NSApp.windows.filter(\.isVisible)
        let build = BourbonBuildDiagnostics.current
        var state = CaptureState(lines: [
            "stage=\(safe(stage)) visible_windows=\(windows.count) app_windows=\(allApplicationWindows.count)",
            "build commit=\(safe(build.gitCommit)) version=\(safe(build.version)) " +
                "number=\(safe(build.buildNumber)) pid=\(ProcessInfo.processInfo.processIdentifier)",
            accessibilityState()
        ])

        let compositorWindows = compositorWindowDetails()
        state.compositorWindowCount = compositorWindows.count
        state.lines.append(contentsOf: compositorWindows)

        BourbonLicenseDiagnostics.record(
            "license.ui.window_hierarchy.started",
            detail: "stage=\(safe(stage)) windows=\(windows.count)"
        )

        for (windowIndex, window) in windows.enumerated() {
            capture(window: window, index: windowIndex, state: &state)
        }

        let modalCount = windows.filter { NSApp.modalWindow === $0 }.count
        let code = "surface_w\(windows.count)_p\(state.playerViewCount)" +
            "_cg\(state.compositorWindowCount)_i\(state.introMarkerCount)" +
            "_l\(state.licenseMarkerCount)_m\(modalCount)"
        let completion = "stage=\(safe(stage)) code=\(code) views=\(state.viewCount)"
        state.lines.append("completed \(completion)")
        BourbonLicenseDiagnostics.record("license.ui.window_hierarchy.completed", detail: completion)
        return Snapshot(code: code, report: state.lines.joined(separator: "\n"))
    }

    private static func capture(window: NSWindow, index: Int, state: inout CaptureState) {
        let windowDetail = [
            "index=\(index)",
            "number=\(window.windowNumber)",
            "class=\(className(window))",
            "frame=\(rect(window.frame))",
            "level=\(window.level.rawValue)",
            "style=\(window.styleMask.rawValue)",
            "visible=\(window.isVisible)",
            "key=\(window.isKeyWindow)",
            "main=\(window.isMainWindow)",
            "can_key=\(window.canBecomeKey)",
            "can_main=\(window.canBecomeMain)",
            "alpha=\(number(window.alphaValue))",
            "ignores_mouse=\(window.ignoresMouseEvents)",
            "accepts_mouse_moved=\(window.acceptsMouseMovedEvents)",
            "modal=\(NSApp.modalWindow === window)",
            "sheet=\(window.sheetParent != nil)",
            "attached_sheet=\(window.attachedSheet != nil)",
            "parent=\(window.parent?.windowNumber ?? -1)",
            "children=\(window.childWindows?.count ?? 0)",
            "first_responder=\(window.firstResponder.map(className) ?? "none")",
            "center_hit=\(windowCenterHitClass(window))"
        ].joined(separator: " ")
        state.lines.append("window \(windowDetail)")
        BourbonLicenseDiagnostics.record("license.ui.window", detail: windowDetail)

        if let contentView = window.contentView {
            visit(contentView, depth: 0, windowIndex: index, state: &state)
        }
    }

    @discardableResult
    static func copyCurrentReport(stage: String) -> Snapshot {
        let snapshot = capture(stage: stage)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snapshot.report, forType: .string)
        BourbonLicenseDiagnostics.record("license.ui.window_hierarchy.copied", detail: "stage=\(safe(stage))")
        return snapshot
    }

    private static func visit(
        _ view: NSView,
        depth: Int,
        windowIndex: Int,
        state: inout CaptureState
    ) {
        guard state.viewCount < maximumViews else { return }
        state.viewCount += 1

        let viewClass = className(view)
        let identifier = safe(view.identifier?.rawValue ?? "none")
        let markerRole = (view as? BourbonSurfaceMarkerNSView)?.role ?? "none"
        let hitClass = view.hitTest(NSPoint(x: view.bounds.midX, y: view.bounds.midY)).map(className) ?? "none"
        let hostingOwner = nearestHostingOwner(of: view)
        let detail = [
            "window=\(windowIndex)",
            "depth=\(depth)",
            "class=\(viewClass)",
            "identifier=\(identifier)",
            "role=\(safe(markerRole))",
            "frame=\(rect(frameInWindow(view)))",
            "hidden=\(view.isHidden)",
            "hidden_ancestor=\(view.isHiddenOrHasHiddenAncestor)",
            "alpha=\(number(view.alphaValue))",
            "accepts_first=\(view.acceptsFirstResponder)",
            "can_key_view=\(view.canBecomeKeyView)",
            "focus_ring=\(view.focusRingType.rawValue)",
            "wants_layer=\(view.wantsLayer)",
            "hit_center=\(hitClass)",
            "mouse_moves_window=\(view.mouseDownCanMoveWindow)",
            "touch=\(view.acceptsTouchEvents)",
            "hosting_owner=\(hostingOwner)"
        ].joined(separator: " ")
        state.lines.append("view \(detail)")
        BourbonLicenseDiagnostics.record("license.ui.view", detail: detail)

        if view is BourbonPlayerSurfaceNSView {
            state.playerViewCount += 1
        }
        if markerRole == "intro_surface" {
            state.introMarkerCount += 1
        } else if markerRole == "license_overlay" {
            state.licenseMarkerCount += 1
        }

        for subview in view.subviews {
            visit(
                subview,
                depth: depth + 1,
                windowIndex: windowIndex,
                state: &state
            )
        }
    }

    private static func windowCenterHitClass(_ window: NSWindow) -> String {
        guard let contentView = window.contentView else { return "none" }
        let point = NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        return contentView.hitTest(point).map(className) ?? "none"
    }

    private static func accessibilityState() -> String {
        let workspace = NSWorkspace.shared
        return [
            "accessibility",
            "voiceover=\(workspace.isVoiceOverEnabled)",
            "increase_contrast=\(workspace.accessibilityDisplayShouldIncreaseContrast)",
            "reduce_transparency=\(workspace.accessibilityDisplayShouldReduceTransparency)",
            "reduce_motion=\(workspace.accessibilityDisplayShouldReduceMotion)",
            "invert_colors=\(workspace.accessibilityDisplayShouldInvertColors)"
        ].joined(separator: " ")
    }

    private static func compositorWindowDetails() -> [String] {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return ["compositor unavailable=true"]
        }

        let processIdentifier = ProcessInfo.processInfo.processIdentifier
        return windowInfo.compactMap { entry in
            guard let owner = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  owner.int32Value == processIdentifier else {
                return nil
            }
            let number = (entry[kCGWindowNumber as String] as? NSNumber)?.intValue ?? -1
            let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
            let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? -1
            let name = entry[kCGWindowName as String] as? String ?? "none"
            let bounds = String(describing: entry[kCGWindowBounds as String] ?? "none")
            return "compositor number=\(number) layer=\(layer) alpha=\(alpha) " +
                "name=\(safe(name)) bounds=\(safe(bounds))"
        }
    }

    private static func nearestHostingOwner(of view: NSView) -> String {
        var candidate: NSView? = view
        while let current = candidate {
            let name = className(current)
            if name.localizedCaseInsensitiveContains("hosting") {
                return name
            }
            candidate = current.superview
        }
        return "none"
    }

    private static func frameInWindow(_ view: NSView) -> NSRect {
        guard let superview = view.superview else { return view.frame }
        return superview.convert(view.frame, to: nil)
    }

    private static func className(_ value: AnyObject) -> String {
        safe(NSStringFromClass(type(of: value)))
    }

    private static func rect(_ value: NSRect) -> String {
        [value.origin.x, value.origin.y, value.size.width, value.size.height]
            .map(number)
            .joined(separator: ",")
    }

    private static func number(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }

    private static func safe(_ value: String) -> String {
        String(value.replacingOccurrences(of: "\n", with: "_").prefix(180))
    }
}

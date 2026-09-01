//
//  DiagnosticAppInstallerView.swift
//  Whisky
//

import AppKit
import os
import SwiftUI
import WhiskyKit

// swiftlint:disable file_length

private let diagnosticInstallerLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.unblockerfire.Bourbon",
    category: "diagnostic-installer"
)

@MainActor
final class DiagnosticInstallationCoordinator: ObservableObject {
    @Published private(set) var phase: DiagnosticInstallationPhase

    let sourceURL: URL
    let sourceIdentity: DiagnosticBuildIdentity
    private let copier: DiagnosticAppBundleCopier
    private var lastLoggedPercent = -1

    init(
        bundle: Bundle = .main,
        copier: DiagnosticAppBundleCopier = DiagnosticAppBundleCopier()
    ) {
        sourceURL = bundle.bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        sourceIdentity = DiagnosticBuildIdentity.load(from: sourceURL)
        self.copier = copier
        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        if DiagnosticAppInstallationPolicy.requiresInstallation(
            bundleURL: sourceURL,
            displayName: displayName
        ) {
            phase = .ready
        } else {
            phase = .notRequired
        }

        recordCompletedRelaunchIfNeeded()
    }

    var requiresSetup: Bool {
        if case .notRequired = phase { return false }
        return true
    }

    func acceptDrag() {
        if let existing = DiagnosticAppInstallationPolicy.inspectExistingCopy() {
            phase = .confirmReplacement(existing)
        } else {
            beginCopy(replaceExisting: false)
        }
    }

    func replaceExistingCopy() {
        beginCopy(replaceExisting: true)
    }

    func cancelReplacement() {
        phase = .ready
    }

    func retry() {
        phase = .ready
    }

    func closeTemporaryInstance() {
        NSApp.terminate(nil)
    }

    func openInstalledCopy() {
        let destination = DiagnosticAppInstallationPolicy.destinationURL
        guard DiagnosticAppInstallationPolicy.isInstalledDestination(destination),
              FileManager.default.fileExists(atPath: destination.path) else {
            phase = .failure("The verified Applications copy could not be found.")
            return
        }

        diagnosticInstallerLogger.notice(
            "app.install.relaunch.requested destination=/Applications/Bourbon_Diagnostic.app"
        )
        let configuration = NSWorkspace.OpenConfiguration()
        var environment = ProcessInfo.processInfo.environment
        environment["BOURBON_DIAGNOSTIC_RELAUNCH_EXPECTED"] = "1"
        configuration.environment = environment
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { application, error in
            Task { @MainActor [weak self] in
                if let error {
                    let description = diagnosticSafeDescription(error)
                    diagnosticInstallerLogger.error(
                        "app.install.relaunch.failed description=\(description, privacy: .public)"
                    )
                    self?.phase = .failure("Bourbon Diagnostic could not be opened. \(description)")
                    return
                }
                guard let launchedURL = application?.bundleURL,
                      DiagnosticAppInstallationPolicy.isInstalledDestination(launchedURL) else {
                    self?.phase = .failure("macOS did not confirm that Bourbon Diagnostic opened.")
                    return
                }
                diagnosticInstallerLogger.notice(
                    "app.install.relaunch.requested status=success verified_destination=true"
                )
                NSApp.terminate(nil)
            }
        }
    }

    private func beginCopy(replaceExisting: Bool) {
        let initialProgress = DiagnosticCopyProgress(
            bytesCopied: 0,
            totalBytes: 1,
            filesCopied: 0,
            totalFiles: 1
        )
        phase = .copying(initialProgress)
        lastLoggedPercent = -1
        diagnosticInstallerLogger.notice(
            """
            app.install.copy.started source=running_bundle \
            destination=/Applications/Bourbon_Diagnostic.app replace=\(replaceExisting)
            """
        )
        let sourceURL = self.sourceURL
        let copier = self.copier

        Task { [weak self] in
            guard let self else { return }
            if replaceExisting, !await stopRunningInstalledCopies() {
                phase = .failure(
                    "The previous Bourbon Diagnostic process could not be closed safely. " +
                        "Quit or Force Quit that diagnostic copy, then try again."
                )
                return
            }
            launchCopy(sourceURL: sourceURL, copier: copier, replaceExisting: replaceExisting)
        }
    }

    private func launchCopy(
        sourceURL: URL,
        copier: DiagnosticAppBundleCopier,
        replaceExisting: Bool
    ) {
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let destination = try copier.copy(
                    source: sourceURL,
                    replaceExisting: replaceExisting
                ) { report in
                    Task { @MainActor [weak self] in
                        self?.receiveProgress(report)
                    }
                }
                await self?.copyCompleted(destination: destination)
            } catch {
                await self?.copyFailed(error)
            }
        }
    }

    private func stopRunningInstalledCopies() async -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return true }
        let destination = DiagnosticAppInstallationPolicy.destinationURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let installedCopies = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { application in
                guard application.processIdentifier != currentProcessIdentifier,
                      let bundleURL = application.bundleURL else {
                    return false
                }
                return bundleURL.standardizedFileURL.resolvingSymlinksInPath() == destination
            }

        guard !installedCopies.isEmpty else { return true }
        diagnosticInstallerLogger.notice(
            "app.install.previous_process.detected count=\(installedCopies.count)"
        )
        for application in installedCopies {
            diagnosticInstallerLogger.notice(
                "app.install.previous_process.terminate_requested pid=\(application.processIdentifier)"
            )
            application.terminate()
        }

        if await waitForTermination(installedCopies, attempts: 30) {
            diagnosticInstallerLogger.notice("app.install.previous_process.terminated forced=false")
            return true
        }

        for application in installedCopies where !application.isTerminated {
            diagnosticInstallerLogger.notice(
                "app.install.previous_process.force_terminate_requested pid=\(application.processIdentifier)"
            )
            application.forceTerminate()
        }
        let terminated = await waitForTermination(installedCopies, attempts: 20)
        diagnosticInstallerLogger.notice(
            "app.install.previous_process.terminated forced=true success=\(terminated)"
        )
        return terminated
    }

    private func waitForTermination(
        _ applications: [NSRunningApplication],
        attempts: Int
    ) async -> Bool {
        for _ in 0..<attempts {
            if applications.allSatisfy(\.isTerminated) {
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return applications.allSatisfy(\.isTerminated)
    }

    private func receiveProgress(_ progress: DiagnosticCopyProgress) {
        phase = .copying(progress)
        let percent = Int(progress.fractionCompleted * 100)
        if percent == 100 || percent >= lastLoggedPercent + 5 {
            lastLoggedPercent = percent
            diagnosticInstallerLogger.notice(
                """
                app.install.copy.progress percent=\(percent) \
                bytes=\(progress.bytesCopied) files=\(progress.filesCopied)
                """
            )
        }
    }

    private func copyCompleted(destination: URL) {
        guard DiagnosticAppInstallationPolicy.isInstalledDestination(destination) else {
            phase = .failure("The copied app resolved to an unexpected location.")
            return
        }
        diagnosticInstallerLogger.notice(
            "app.install.copy.completed destination=/Applications/Bourbon_Diagnostic.app verified=true"
        )
        phase = .complete
    }

    private func copyFailed(_ error: Error) {
        let description = diagnosticSafeDescription(error)
        diagnosticInstallerLogger.error(
            "app.install.copy.failed description=\(description, privacy: .public)"
        )
        phase = .failure(description)
    }

    private func recordCompletedRelaunchIfNeeded() {
        guard ProcessInfo.processInfo.environment["BOURBON_DIAGNOSTIC_RELAUNCH_EXPECTED"] == "1" else {
            return
        }
        let resolvedPath = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
        if DiagnosticAppInstallationPolicy.isInstalledDestination(resolvedPath) {
            diagnosticInstallerLogger.notice(
                "app.install.relaunch.completed path=/Applications/Bourbon_Diagnostic.app verified=true"
            )
        } else {
            diagnosticInstallerLogger.error(
                "app.install.relaunch.failed reason=unexpected_bundle_path"
            )
        }
    }
}

enum DiagnosticInstallationPhase: Equatable {
    case notRequired
    case ready
    case confirmReplacement(DiagnosticInstalledCopy)
    case copying(DiagnosticCopyProgress)
    case complete
    case failure(String)
}

struct DiagnosticAppInstallerView: View {
    @ObservedObject var coordinator: DiagnosticInstallationCoordinator

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

            Group {
                switch coordinator.phase {
                case .notRequired:
                    EmptyView()
                case .ready:
                    dragScreen
                case .confirmReplacement(let existing):
                    replacementScreen(existing)
                case .copying(let progress):
                    copyingScreen(progress)
                case .complete:
                    completionScreen
                case .failure(let message):
                    failureScreen(message)
                }
            }
            .foregroundStyle(.primary)
            .padding(48)
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private var dragScreen: some View {
        VStack(spacing: 30) {
            installerHeader(
                title: "Move Bourbon Diagnostic to Applications",
                subtitle: "Drag Bourbon Diagnostic to Applications"
            )
            DiagnosticDragTarget(onAccepted: coordinator.acceptDrag)
                .frame(width: 620, height: 190)
            buildIdentity
        }
    }

    private func replacementScreen(_ existing: DiagnosticInstalledCopy) -> some View {
        VStack(spacing: 24) {
            installerHeader(
                title: "Replace the existing diagnostic copy?",
                subtitle: "Bourbon inspected the copy already in Applications. " +
                    "It will not be replaced without permission."
            )
            HStack(spacing: 20) {
                identityCard(title: "Existing copy", identity: existing.identity)
                Image(systemName: "arrow.right")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                identityCard(title: "This build", identity: coordinator.sourceIdentity)
            }
            HStack(spacing: 12) {
                Button("Keep Existing") { coordinator.cancelReplacement() }
                    .buttonStyle(.bordered)
                Button("Replace Bourbon Diagnostic") { coordinator.replaceExistingCopy() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
        }
    }

    private func copyingScreen(_ progress: DiagnosticCopyProgress) -> some View {
        VStack(spacing: 28) {
            DiagnosticAppIcon(image: NSApp.applicationIconImage, size: 96)
            installerHeader(
                title: "Copying Bourbon Diagnostic to Applications…",
                subtitle: "Copying the complete app bundle. Your Bourbon data is not being changed."
            )
            VStack(spacing: 12) {
                ProgressView(value: progress.fractionCompleted)
                    .progressViewStyle(.linear)
                    .tint(.orange)
                Text("\(Int(progress.fractionCompleted * 100))%")
                    .font(.title2.monospacedDigit().weight(.semibold))
                Text("\(progress.filesCopied) of \(progress.totalFiles) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 520)
            buildIdentity
        }
    }

    private var completionScreen: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
            installerHeader(
                title: "Bourbon Diagnostic is ready.",
                subtitle: "It has been copied to your Applications folder."
            )
            HStack(spacing: 12) {
                Button("Close") { coordinator.closeTemporaryInstance() }
                    .buttonStyle(.bordered)
                Button("Open Bourbon Diagnostic") { coordinator.openInstalledCopy() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
            buildIdentity
        }
    }

    private func failureScreen(_ message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 58))
                .foregroundStyle(.orange)
            installerHeader(title: "Bourbon Diagnostic could not be copied.", subtitle: message)
            HStack(spacing: 12) {
                Button("Close") { coordinator.closeTemporaryInstance() }
                    .buttonStyle(.bordered)
                Button("Try Again") { coordinator.retry() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
            buildIdentity
        }
    }

    private func installerHeader(title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var buildIdentity: some View {
        Text("Bourbon Diagnostic • Build \(coordinator.sourceIdentity.versionDisplay) • " +
             "Commit \(coordinator.sourceIdentity.commitDisplay)")
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }

    private func identityCard(title: String, identity: DiagnosticBuildIdentity) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline)
            Text("Build \(identity.versionDisplay)")
            Text("Commit \(identity.commitDisplay)")
                .font(.body.monospaced())
        }
        .padding(18)
        .frame(width: 245, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }
}

private func diagnosticSafeDescription(_ error: Error) -> String {
    let description = error.localizedDescription.replacingOccurrences(
        of: FileManager.default.homeDirectoryForCurrentUser.path,
        with: "~"
    )
    return String(description.prefix(1_000))
}

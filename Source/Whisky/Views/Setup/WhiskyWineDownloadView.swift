import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit

struct WhiskyWineDownloadView: View {
    @Binding var tarLocation: URL
    @Binding var runtimeVersion: String?
    @Binding var runtimeSHA256: String?
    @Binding var manualRuntimeArchive: Bool
    @Binding var path: [SetupStage]

    @State private var downloadTask: URLSessionDownloadTask?
    @State private var observation: NSKeyValueObservation?
    @State private var downloadProgress: Double = 0
    @State private var verifyingDownload = false
    @State private var downloadError: String?
    @State private var manualDownloadMessage: String?
    @State private var localArchivePanel: NSOpenPanel?
    // A selection from the manual flow and a URLSession completion can arrive in
    // either order.  This token makes only the currently active acquisition
    // attempt eligible to mutate navigation state.
    @State private var downloadAttemptID = UUID()

    var body: some View {
        BourbonPanelBackdrop {
            VStack(spacing: 22) {
                Spacer(minLength: 0)
                downloadPanel
                Spacer(minLength: 0)
            }
        }
        .navigationTitle("Download BourbonWine")
        .navigationBarBackButtonHidden(true)
        .onAppear {
            download()
        }
        .onDisappear {
            cancelActiveDownload()
        }
    }

    private var downloadPanel: some View {
        BourbonFloatingPanel(maxWidth: 560) {
            VStack(spacing: 22) {
                Text("Download BourbonWine")
                    .font(.largeTitle.bold())
                Text("Bourbon is downloading the runtime it uses to open Windows apps.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                downloadStatus
                Button("Install BourbonWine Manually") { chooseLocalArchive() }
                    .buttonStyle(BourbonSecondaryButtonStyle())
                    .help("Use a BourbonWine archive already saved on this Mac.")
                Button("Download BourbonWine Manually") { downloadManually() }
                    .buttonStyle(BourbonSecondaryButtonStyle())
                    .help("Save the official BourbonWine archive for manual installation.")
                if let manualDownloadMessage {
                    Text(manualDownloadMessage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button("Cancel") { cancelSetupFlow() }
                    .buttonStyle(BourbonSecondaryButtonStyle())
                    .help("Return to Setup check without installing BourbonWine.")
            }
        }
    }

    @ViewBuilder
    private var downloadStatus: some View {
        if let downloadError {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 42))
                .foregroundStyle(BourbonStyle.amber)
            Text(downloadError)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { download() }
                .buttonStyle(BourbonPrimaryButtonStyle())
        } else if verifyingDownload {
            ProgressView()
                .controlSize(.large)
            Text("Verifying BourbonWine…")
                .foregroundStyle(.secondary)
        } else {
            ProgressView(value: downloadProgress)
                .frame(width: 320)
            Text("\(Int(downloadProgress * 100))%")
                .foregroundStyle(.secondary)
        }
    }

    // swiftlint:disable:next function_body_length
    private func download() {
        let attemptID = UUID()
        downloadAttemptID = attemptID
        downloadError = nil
        manualDownloadMessage = nil
        downloadProgress = 0
        verifyingDownload = false
        manualRuntimeArchive = false
        runtimeSHA256 = nil
        cancelActiveDownload(invalidateAttempt: false)

        Task {
            do {
                if await existingRuntimePreventsDownload(for: attemptID) { return }
                let runtimeInfo = try await WhiskyWineInstaller.latestRuntimeInfo()
                guard isCurrentDownloadAttempt(attemptID) else { return }
                let sourceURL = runtimeInfo.archiveUrl
                runtimeVersion = runtimeInfo.version
                runtimeSHA256 = runtimeInfo.sha256

                let task = URLSession(configuration: .ephemeral).downloadTask(with: sourceURL) { url, response, error in
                    DispatchQueue.main.async {
                        guard isCurrentDownloadAttempt(attemptID) else { return }
                        if let error {
                            verifyingDownload = false
                            downloadError = error.localizedDescription
                            return
                        }

                        guard let url else {
                            verifyingDownload = false
                            downloadError = "Download failed."
                            return
                        }

                        verifyingDownload = true
                        Task {
                            do {
                                let persistedArchive = try await Task.detached(priority: .userInitiated) {
                                    try WhiskyWineInstaller.persistDownloadedArchive(
                                        at: url,
                                        response: response,
                                        sourceURL: sourceURL,
                                        expectedSHA256: runtimeInfo.sha256
                                    )
                                }.value
                                guard isCurrentDownloadAttempt(attemptID) else { return }
                                verifyingDownload = false
                                tarLocation = persistedArchive
                                path.append(.whiskyWineInstall)
                            } catch is CancellationError {
                                guard isCurrentDownloadAttempt(attemptID) else { return }
                                verifyingDownload = false
                                downloadError = "BourbonWine download was cancelled. You can retry safely."
                            } catch {
                                guard isCurrentDownloadAttempt(attemptID) else { return }
                                verifyingDownload = false
                                downloadError = error.localizedDescription
                            }
                        }
                    }
                }

                downloadTask = task
                observation = task.observe(\.countOfBytesReceived) { task, _ in
                    DispatchQueue.main.async {
                        guard isCurrentDownloadAttempt(attemptID) else { return }
                        let expected = Double(task.countOfBytesExpectedToReceive)
                        guard expected > 0 else { return }
                        downloadProgress = Double(task.countOfBytesReceived) / expected
                    }
                }

                task.resume()
            } catch {
                guard isCurrentDownloadAttempt(attemptID) else { return }
                downloadError = error.localizedDescription
            }
        }
    }

    private func existingRuntimePreventsDownload(for attemptID: UUID) async -> Bool {
        let discovery = await WhiskyWineInstaller.discoverRuntime()
        guard isCurrentDownloadAttempt(attemptID) else { return true }
        switch RuntimeSetupFlowPolicy.automaticDownloadAction(for: discovery.state) {
        case .showReadyWithoutDismissing:
            WhiskyWineInstaller.recordRuntimeEvent("runtime.download.reason", detail: "existing_runtime_ready")
            // This is a second, asynchronous observation after Setup check
            // elected to enter this flow. It must never dismiss the flow by
            // mutating the navigation path. The user can explicitly cancel.
            WhiskyWineInstaller.recordRuntimeEvent("runtime.download.recheck_ready", detail: "state=ready")
            downloadError = "BourbonWine is now ready. Cancel Setup to return to Bourbon."
            return true
        case .showGatekeeperRecovery:
            WhiskyWineInstaller.recordRuntimeEvent("runtime.download.reason", detail: "gatekeeper_blocked")
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.download.skipped_existing",
                detail: "state=gatekeeper_blocked"
            )
            path.append(.whiskyWineGatekeeperRecovery)
            return true
        case .continueDownload:
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.download.reason",
                detail: discovery.state.rawValue
            )
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.download.required",
                detail: "state=\(discovery.state.rawValue)"
            )
            return false
        }
    }

    private func chooseLocalArchive() {
        // A manual archive supersedes the automatic acquisition attempt. This
        // prevents a late automatic completion from pushing a second install
        // destination over the manual installer.
        if RuntimeSetupFlowPolicy.manualArchiveSupersedesAutomaticDownload {
            cancelActiveDownload()
        }
        let panel = NSOpenPanel()
        localArchivePanel = panel
        defer {
            localArchivePanel = nil
        }
        panel.allowedContentTypes = manualArchiveContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                WhiskyWineInstaller.recordRuntimeEvent("runtime.manual.install.started")
                manualRuntimeArchive = true
                // The selected archive is authoritative for its own manifest
                // version. This must match the exact artifact opened by the
                // companion manual-download button, not this app bundle.
                runtimeVersion = nil
                runtimeSHA256 = nil
                tarLocation = try WhiskyWineInstaller.persistLocalArchive(at: url)
                path.append(.whiskyWineInstall)
            } catch {
                WhiskyWineInstaller.recordRuntimeEvent(
                    "runtime.manual.install.failed",
                    detail: "error=\(error.localizedDescription)"
                )
                downloadError = error.localizedDescription
            }
        }
    }

    private var manualArchiveContentTypes: [UTType] {
        WhiskyWineInstaller.supportedManualArchiveExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
    }

    private func downloadManually() {
        Task {
            do {
                let archive = try await WhiskyWineInstaller.downloadLatestRuntimeForManualInstallation()
                manualDownloadMessage =
                    "Saved \(archive.lastPathComponent) to Downloads. Select it with Install BourbonWine Manually."
            } catch {
                downloadError = "Could not open the BourbonWine download: \(error.localizedDescription)"
            }
        }
    }

    private func cancelSetupFlow() {
        cancelActiveDownload()
        path.removeAll()
    }

    private func cancelActiveDownload(invalidateAttempt: Bool = true) {
        if invalidateAttempt {
            downloadAttemptID = UUID()
        }
        downloadTask?.cancel()
        downloadTask = nil
        observation?.invalidate()
        observation = nil
    }

    private func isCurrentDownloadAttempt(_ attemptID: UUID) -> Bool {
        downloadAttemptID == attemptID
    }
}

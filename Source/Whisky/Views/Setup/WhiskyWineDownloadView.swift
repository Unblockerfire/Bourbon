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
            downloadTask?.cancel()
            observation?.invalidate()
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
        downloadError = nil
        manualDownloadMessage = nil
        downloadProgress = 0
        verifyingDownload = false
        manualRuntimeArchive = false
        runtimeSHA256 = nil
        downloadTask?.cancel()
        observation?.invalidate()

        Task {
            do {
                if await existingRuntimePreventsDownload() { return }
                let runtimeInfo = try await WhiskyWineInstaller.latestRuntimeInfo()
                let sourceURL = runtimeInfo.archiveUrl
                runtimeVersion = runtimeInfo.version
                runtimeSHA256 = runtimeInfo.sha256

                let task = URLSession(configuration: .ephemeral).downloadTask(with: sourceURL) { url, response, error in
                    DispatchQueue.main.async {
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
                                verifyingDownload = false
                                tarLocation = persistedArchive
                                path.append(.whiskyWineInstall)
                            } catch is CancellationError {
                                verifyingDownload = false
                                downloadError = "BourbonWine download was cancelled. You can retry safely."
                            } catch {
                                verifyingDownload = false
                                downloadError = error.localizedDescription
                            }
                        }
                    }
                }

                downloadTask = task
                observation = task.observe(\.countOfBytesReceived) { task, _ in
                    DispatchQueue.main.async {
                        let expected = Double(task.countOfBytesExpectedToReceive)
                        guard expected > 0 else { return }
                        downloadProgress = Double(task.countOfBytesReceived) / expected
                    }
                }

                task.resume()
            } catch {
                downloadError = error.localizedDescription
            }
        }
    }

    private func existingRuntimePreventsDownload() async -> Bool {
        let discovery = await WhiskyWineInstaller.discoverRuntime()
        switch discovery.state {
        case .ready:
            WhiskyWineInstaller.recordRuntimeEvent("runtime.download.reason", detail: "existing_runtime_ready")
            WhiskyWineInstaller.recordRuntimeEvent("runtime.download.skipped_existing", detail: "state=ready")
            path.removeAll()
            return true
        case .gatekeeperBlocked:
            WhiskyWineInstaller.recordRuntimeEvent("runtime.download.reason", detail: "gatekeeper_blocked")
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.download.skipped_existing",
                detail: "state=gatekeeper_blocked"
            )
            path.append(.whiskyWineGatekeeperRecovery)
            return true
        case .installedUnverified, .verificationFailed:
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.download.reason",
                detail: "existing_runtime_\(discovery.state.rawValue)"
            )
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.download.skipped_existing",
                detail: "state=\(discovery.state.rawValue)"
            )
            downloadError = discovery.errorDescription
                ?? "BourbonWine is already installed. Retry its readiness check before replacing it."
            return true
        case .missing, .corruptOrIncomplete, .unsupported:
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
}

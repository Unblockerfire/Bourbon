import AppKit
import SwiftUI
import WhiskyKit

struct WhiskyWineDownloadView: View {
    @Binding var tarLocation: URL
    @Binding var runtimeVersion: String?
    @Binding var manualRuntimeArchive: Bool
    @Binding var path: [SetupStage]

    @State private var downloadTask: URLSessionDownloadTask?
    @State private var observation: NSKeyValueObservation?
    @State private var downloadProgress: Double = 0
    @State private var downloadError: String?
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
                    .help("Open the official BourbonWine archive download in your browser.")
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
        } else {
            ProgressView(value: downloadProgress)
                .frame(width: 320)
            Text("\(Int(downloadProgress * 100))%")
                .foregroundStyle(.secondary)
        }
    }

    private func download() {
        downloadError = nil
        downloadProgress = 0
        manualRuntimeArchive = false
        downloadTask?.cancel()
        observation?.invalidate()

        Task {
            do {
                if await existingRuntimePreventsDownload() { return }
                if try loadBundledDiagnosticRuntime() { return }

                let runtimeInfo = try await WhiskyWineInstaller.latestRuntimeInfo()
                let sourceURL = runtimeInfo.archiveUrl
                runtimeVersion = runtimeInfo.version

                let task = URLSession(configuration: .ephemeral).downloadTask(with: sourceURL) { url, response, error in
                    DispatchQueue.main.async {
                        if let error {
                            downloadError = error.localizedDescription
                            return
                        }

                        guard let url else {
                            downloadError = "Download failed."
                            return
                        }

                        do {
                            tarLocation = try WhiskyWineInstaller.persistDownloadedArchive(
                                at: url,
                                response: response,
                                sourceURL: sourceURL
                            )
                            path.append(.whiskyWineInstall)
                        } catch {
                            downloadError = error.localizedDescription
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
            WhiskyWineInstaller.recordRuntimeEvent("runtime.download.skipped_existing", detail: "state=ready")
            path.removeAll()
            return true
        case .gatekeeperBlocked:
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.download.skipped_existing",
                detail: "state=gatekeeper_blocked"
            )
            path.append(.whiskyWineGatekeeperRecovery)
            return true
        case .installedUnverified, .verificationFailed:
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.download.skipped_existing",
                detail: "state=\(discovery.state.rawValue)"
            )
            downloadError = discovery.errorDescription
                ?? "BourbonWine is already installed. Retry its readiness check before replacing it."
            return true
        case .missing, .corruptOrIncomplete, .unsupported:
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.download.required",
                detail: "state=\(discovery.state.rawValue)"
            )
            return false
        }
    }

    private func loadBundledDiagnosticRuntime() throws -> Bool {
        guard let bundledRuntime = WhiskyWineInstaller.bundledDiagnosticRuntime() else {
            return false
        }

        runtimeVersion = bundledRuntime.info.runtimeVersion
        tarLocation = try WhiskyWineInstaller.persistLocalArchive(at: bundledRuntime.archive)
        downloadProgress = 1
        path.append(.whiskyWineInstall)
        return true
    }

    private func chooseLocalArchive() {
        let panel = NSOpenPanel()
        localArchivePanel = panel
        defer {
            localArchivePanel = nil
        }
        panel.allowedContentTypes = [.gzip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                WhiskyWineInstaller.recordRuntimeEvent("runtime.manual.install.started")
                manualRuntimeArchive = true
                runtimeVersion = WhiskyWineInstaller.bundledDiagnosticRuntime()?.info.runtimeVersion
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

    private func downloadManually() {
        Task {
            do {
                let runtimeInfo = try await WhiskyWineInstaller.latestRuntimeInfo()
                guard NSWorkspace.shared.open(runtimeInfo.archiveUrl) else {
                    throw CocoaError(.fileNoSuchFile)
                }
            } catch {
                downloadError = "Could not open the BourbonWine download: \(error.localizedDescription)"
            }
        }
    }
}

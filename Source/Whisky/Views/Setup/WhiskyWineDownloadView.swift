import SwiftUI
import WhiskyKit

struct WhiskyWineDownloadView: View {
    @Binding var tarLocation: URL
    @Binding var runtimeVersion: String?
    @Binding var path: [SetupStage]

    @State private var downloadTask: URLSessionDownloadTask?
    @State private var observation: NSKeyValueObservation?
    @State private var downloadProgress: Double = 0
    @State private var downloadError: String?
    @State private var localArchivePanel: NSOpenPanel?
    @State private var retryAttempt = 0

    var body: some View {
        BourbonPanelBackdrop {
            VStack(spacing: 22) {
                Spacer(minLength: 0)

                BourbonFloatingPanel(maxWidth: 560) {
                    VStack(spacing: 22) {
                        Text("Download BourbonWine")
                            .font(.largeTitle.bold())

                        Text("Bourbon is downloading the runtime it uses to open Windows apps.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        if let downloadError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 42))
                                .foregroundStyle(BourbonStyle.amber)

                            Text(downloadError)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button("Retry") {
                                retryAttempt += 1
                                WhiskyWineInstaller.recordRuntimeEvent(
                                    "runtime.retry.started",
                                    detail: "source=setup_download attempt=\(retryAttempt)"
                                )
                                download()
                            }
                            .buttonStyle(BourbonPrimaryButtonStyle())
                        } else {
                            ProgressView(value: downloadProgress)
                                .frame(width: 320)

                            Text("\(Int(downloadProgress * 100))%")
                                .foregroundStyle(.secondary)
                        }

                        Button("Choose Local BourbonWine Archive...") {
                            chooseLocalArchive()
                        }
                        .buttonStyle(BourbonSecondaryButtonStyle())
                        .help("Use a BourbonWine archive already saved on this Mac.")
                    }
                }

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

    private func download() {
        downloadError = nil
        downloadProgress = 0
        downloadTask?.cancel()
        observation?.invalidate()

        Task {
            do {
                if try loadBundledDiagnosticRuntime() { return }

                let runtimeInfo = try await WhiskyWineInstaller.latestRuntimeInfo()
                let sourceURL = runtimeInfo.archiveUrl
                runtimeVersion = runtimeInfo.version

                let task = URLSession(configuration: .ephemeral).downloadTask(with: sourceURL) { url, response, error in
                    DispatchQueue.main.async {
                        if let error {
                            downloadError = error.localizedDescription
                            WhiskyWineInstaller.recordRuntimeEvent(
                                "runtime.ui.finalized",
                                detail: "surface=setup_download outcome=failure stage=download"
                            )
                            return
                        }

                        guard let url else {
                            downloadError = "Download failed."
                            WhiskyWineInstaller.recordRuntimeEvent(
                                "runtime.ui.finalized",
                                detail: "surface=setup_download outcome=failure stage=download"
                            )
                            return
                        }

                        do {
                            WhiskyWineInstaller.recordRuntimeEvent(
                                "runtime.archive.selected",
                                detail: "source=runtime_manifest"
                            )
                            tarLocation = try WhiskyWineInstaller.persistDownloadedArchive(
                                at: url,
                                response: response,
                                sourceURL: sourceURL
                            )
                            path.append(.whiskyWineInstall)
                            WhiskyWineInstaller.recordRuntimeEvent(
                                "runtime.ui.finalized",
                                detail: "surface=setup_download outcome=archive_ready"
                            )
                        } catch {
                            downloadError = error.localizedDescription
                            WhiskyWineInstaller.recordRuntimeEvent(
                                "runtime.ui.finalized",
                                detail: "surface=setup_download outcome=failure"
                            )
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
                WhiskyWineInstaller.recordRuntimeEvent(
                    "runtime.ui.finalized",
                    detail: "surface=setup_download outcome=failure stage=selection"
                )
            }
        }
    }

    private func loadBundledDiagnosticRuntime() throws -> Bool {
        guard let bundledRuntime = WhiskyWineInstaller.bundledDiagnosticRuntime() else {
            return false
        }

        runtimeVersion = bundledRuntime.info.runtimeVersion
        WhiskyWineInstaller.recordRuntimeEvent(
            "runtime.archive.selected",
            detail: "source=bundled_diagnostic_runtime"
        )
        tarLocation = try WhiskyWineInstaller.persistLocalArchive(at: bundledRuntime.archive)
        downloadProgress = 1
        path.append(.whiskyWineInstall)
        WhiskyWineInstaller.recordRuntimeEvent(
            "runtime.ui.finalized",
            detail: "surface=setup_download outcome=archive_ready"
        )
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
                runtimeVersion = nil
                WhiskyWineInstaller.recordRuntimeEvent(
                    "runtime.archive.selected",
                    detail: "source=local_archive"
                )
                tarLocation = try WhiskyWineInstaller.persistLocalArchive(at: url)
                path.append(.whiskyWineInstall)
                WhiskyWineInstaller.recordRuntimeEvent(
                    "runtime.ui.finalized",
                    detail: "surface=setup_download outcome=archive_ready"
                )
            } catch {
                downloadError = error.localizedDescription
                WhiskyWineInstaller.recordRuntimeEvent(
                    "runtime.ui.finalized",
                    detail: "surface=setup_download outcome=failure stage=local_archive"
                )
            }
        }
    }
}

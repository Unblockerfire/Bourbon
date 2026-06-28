import SwiftUI
import WhiskyKit

struct WhiskyWineDownloadView: View {
    @Binding var tarLocation: URL
    @Binding var path: [SetupStage]

    @State private var downloadTask: URLSessionDownloadTask?
    @State private var observation: NSKeyValueObservation?
    @State private var downloadProgress: Double = 0
    @State private var downloadError: String?
    @State private var localArchivePanel: NSOpenPanel?

    var body: some View {
        BourbonBackground {
            BourbonGlassCard(maxWidth: 460) {
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
        }
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
                let runtimeInfo = try await WhiskyWineInstaller.latestRuntimeInfo()
                let sourceURL = runtimeInfo.archiveUrl

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
                tarLocation = try WhiskyWineInstaller.persistLocalArchive(at: url)
                path.append(.whiskyWineInstall)
            } catch {
                downloadError = error.localizedDescription
            }
        }
    }
}

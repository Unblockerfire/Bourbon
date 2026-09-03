import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit

// swiftlint:disable file_length

enum BottleStage {
    case config
    case programs
    case processes
}

// swiftlint:disable:next type_body_length
struct BottleView: View {
    @ObservedObject var bottle: Bottle
    @ObservedObject private var installManager = InstallManager.shared
    @State private var path = NavigationPath()
    @State private var showsEmptyBottlePrompt = true

    private let gridLayout = [GridItem(.adaptive(minimum: 100, maximum: .infinity))]

    var body: some View {
        NavigationStack(path: $path) {
            BourbonBackground {
                ZStack {
                    VStack(spacing: 28) {
                        Spacer(minLength: 24)

                        ScrollView {
                            VStack(alignment: .center, spacing: 28) {
                                recentApplicationsSection
                                browseLibrarySection
                            }
                            .frame(maxWidth: 760)
                            .frame(maxWidth: .infinity)
                            .padding(32)
                        }

                        Spacer(minLength: 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    Button("Install App", systemImage: "square.and.arrow.down") {
                        chooseInstaller()
                    }
                    .disabled(installManager.isInstalling)
                    .help("Install another Windows app into this bottle.")

                    NavigationLink(value: BottleStage.config) {
                        Label("Bottle Settings", systemImage: "gearshape")
                    }
                    .help("Open settings for this bottle.")
                }
            }
            .onAppear {
                updateStartMenu()
            }
            .disabled(!bottle.isAvailable || installManager.presentsModal)
            .navigationTitle(bottle.settings.name)
            .onChange(of: bottle.settings) { oldValue, newValue in
                guard oldValue != newValue else { return }
                BottleVM.shared.bottles = BottleVM.shared.bottles
            }
            .overlay {
                if installManager.presentsModal {
                    installerActivityOverlay
                }
            }
            .navigationDestination(for: BottleStage.self) { stage in
                switch stage {
                case .config:
                    ConfigView(bottle: bottle)
                case .programs:
                    ProgramsView(bottle: bottle, path: $path)
                case .processes:
                    RunningProcessesView(bottle: bottle)
                }
            }
            .navigationDestination(for: Program.self) { program in
                ProgramView(program: program)
            }
        }
    }

    private var emptyState: some View {
        BourbonGlassCard(maxWidth: 480) {
            VStack(spacing: 16) {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(BourbonStyle.amber)

                Text(showsEmptyBottlePrompt ? "No application selected" : "This bottle is ready")
                    .font(.title.bold())

                Text(
                    showsEmptyBottlePrompt
                        ? "Choose an EXE, MSI, or BAT file now, or add one later."
                        : "You can add a Windows application whenever you’re ready."
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button("Choose EXE") {
                        chooseInstaller()
                    }
                    .buttonStyle(BourbonPrimaryButtonStyle())
                    .disabled(installManager.isInstalling)

                    if showsEmptyBottlePrompt {
                        Button("Not Now") {
                            showsEmptyBottlePrompt = false
                        }
                        .buttonStyle(BourbonSecondaryButtonStyle())
                    }
                }
            }
        }
        .help("Choose a Windows installer to add your first app to this bottle.")
    }

    private var recentApplicationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent Applications")
                    .font(.title2.bold())

                Spacer()

                Button {
                    print("TODO: Open recent application settings.")
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(BourbonSecondaryButtonStyle())
                .help("Manage recent applications.")

                Button {
                    chooseInstaller()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(BourbonPrimaryButtonStyle())
                .disabled(installManager.isInstalling)
                .help("Install another Windows app into this bottle.")
            }

            if recentPrograms.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: gridLayout, alignment: .center) {
                    ForEach(recentPrograms, id: \.url) { program in
                        Button {
                            program.run()
                        } label: {
                            VStack(spacing: 8) {
                                programIcon(program)
                                Text(program.name)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(width: 110, height: 96)
                        }
                        .buttonStyle(.plain)
                        .help("Open \(program.name)")
                    }
                }
            }
        }
    }

    private var browseLibrarySection: some View {
        VStack(spacing: 10) {
            NavigationLink(value: BottleStage.programs) {
                Label("Browse installed apps", systemImage: "square.grid.2x2")
                    .frame(maxWidth: 360)
            }
            .buttonStyle(BourbonSecondaryButtonStyle())
            .help("View every installed app Bourbon found in this bottle.")
        }
    }

    private func updateStartMenu() {
        bottle.updateInstalledPrograms()

        let startMenuPrograms = bottle.getStartMenuPrograms()
        for startMenuProgram in startMenuPrograms {
            for program in bottle.programs where
            program.url.path().caseInsensitiveCompare(startMenuProgram.url.path()) == .orderedSame {
                program.pinned = true
                guard !bottle.settings.pins.contains(where: { $0.url == program.url }) else { return }
                bottle.settings.pins.append(PinnedProgram(
                    name: program.name,
                    url: program.url
                ))
            }
        }
    }

    private var installedPrograms: [Program] {
        let hiddenSystemApps = [
            "wine",
            "wine 11",
            "wine configuration",
            "wine file explorer",
            "wine uninstaller",
            "registry editor",
            "command prompt",
            "notepad",
            "wordpad",
            "internet explorer",
            "oleview",
            "winemine"
        ]

        return bottle.programs
            .filter { FileManager.default.fileExists(atPath: $0.url.path(percentEncoded: false)) }
            .filter { program in
                let name = program.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let executable = program.url.deletingPathExtension().lastPathComponent.lowercased()
                return !hiddenSystemApps.contains(name) && !hiddenSystemApps.contains(executable)
            }
            .sorted { $0.name < $1.name }
    }

    private var recentPrograms: [Program] {
        Array(installedPrograms.prefix(3))
    }

    private var installerActivityOverlay: some View {
        Color.black.opacity(0.45)
            .ignoresSafeArea()
            .overlay {
                if let error = installManager.lastError {
                    InstallerErrorCard(
                        error: error,
                        tryAgain: { installManager.retryLastInstall() },
                        cancel: { installManager.clearFinishedInstall() },
                        reportIssue: { reportIssue(for: error) }
                    )
                } else {
                    InstallerProgressCard(
                        status: installManager.progressStage.title,
                        steps: installManager.pipelineSteps
                    )
                }
            }
    }

    private func chooseInstaller() {
        DispatchQueue.main.async {
            guard let url = selectInstaller(startingDirectory: bottle.url.appending(path: "drive_c")) else { return }
            runInstaller(url)
        }
    }

    private func runInstaller(_ url: URL) {
        installManager.startInstall(url, bottle: bottle)
    }

    @ViewBuilder
    private func programIcon(_ program: Program) -> some View {
        if let icon = program.peFile?.bestIcon() {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 48, height: 48)
        } else {
            Image(systemName: "app.dashed")
                .resizable()
                .frame(width: 42, height: 42)
                .foregroundStyle(BourbonStyle.amber)
        }
    }

    private func reportIssue(for error: InstallerErrorInfo) {
        BourbonReportCenter.openInstallerReport(
            bottleName: error.bottleName,
            installerURL: error.installerURL,
            errorMessage: error.message
        )
    }
}

enum InstallStage: String {
    case choosingInstaller
    case analyzingInstaller
    case checkingCompatibility
    case launchingInstaller
    case waitingForInstaller
    case refreshingAppList
    case cancelling
    case completed
    case cancelled
    case failed

    var title: String {
        switch self {
        case .choosingInstaller:
            return "Choosing installer..."
        case .analyzingInstaller:
            return "Analyzing installer..."
        case .checkingCompatibility:
            return "Checking compatibility..."
        case .launchingInstaller:
            return "Launching installer..."
        case .waitingForInstaller:
            return "Waiting for installer to finish..."
        case .refreshingAppList:
            return "Refreshing app list..."
        case .cancelling:
            return "Cancelling installation..."
        case .completed:
            return "Install finished."
        case .cancelled:
            return "Installation cancelled."
        case .failed:
            return "Install failed."
        }
    }
}

extension InstallStage {
    init(workflow: InstallerWorkflow) {
        switch workflow.state {
        case .idle:
            self = .choosingInstaller
        case .finalizing:
            self = .refreshingAppList
        case .cancelling:
            self = .cancelling
        case .succeeded:
            self = .completed
        case .failed:
            self = .failed
        case .cancelled:
            self = .cancelled
        case .running:
            switch workflow.activity {
            case .opening, .looking, .metadata:
                self = .analyzingInstaller
            case .architecture, .searching, .preparing, .recovering:
                self = .checkingCompatibility
            case .launching:
                self = .launchingInstaller
            case .installing:
                self = .waitingForInstaller
            case .refreshing:
                self = .refreshingAppList
            case .done:
                self = .completed
            }
        }
    }
}

@MainActor
final class InstallManager: ObservableObject {
    static let shared = InstallManager()

    @Published private(set) var workflow = InstallerWorkflow()
    @Published var activeBottleName: String?
    @Published var installerName: String?
    @Published var startedAt: Date?
    @Published var lastError: InstallerErrorInfo?
    @Published var noticeMessage: String?
    @Published var successMessage: String?

    private var lastInstallerURL: URL?
    private var lastBottle: Bottle?
    private var installTask: Task<Void, Never>?
    private init() {}

    var workflowState: InstallerWorkflowState { workflow.state }
    var isInstalling: Bool { workflow.presentsProgress }
    var presentsModal: Bool { workflow.presentsProgress || workflow.state == .failed }
    var canCancel: Bool { workflow.canCancel }
    var progressStage: InstallStage { InstallStage(workflow: workflow) }
    var progressDetail: String { workflow.detail }
    var pipelineSteps: [InstallerPipelineStep] { InstallerPipelineStep.makeSteps(for: workflow) }

    func startInstall(_ url: URL, bottle: Bottle) {
        guard workflow.canStart else {
            noticeMessage = "You have an install in progress. Please wait for it to finish before starting another."
            return
        }

        lastInstallerURL = url
        lastBottle = bottle
        lastError = nil
        noticeMessage = nil
        successMessage = nil
        let installID = workflow.start(detail: "Opening \(url.lastPathComponent)...")
        activeBottleName = bottle.settings.name
        installerName = url.lastPathComponent
        startedAt = Date()
        update(.analyzingInstaller, detail: "Opening \(url.lastPathComponent)...", installID: installID)

        installTask = Task(priority: .userInitiated) {
            await runInstall(url, bottle: bottle, installID: installID)
        }
    }

    func retryLastInstall() {
        guard let lastInstallerURL, let lastBottle else { return }
        workflow.clearTerminalState()
        startInstall(lastInstallerURL, bottle: lastBottle)
    }

    func chooseAnotherInstaller() {
        guard let lastBottle else { return }
        if let url = selectInstaller(startingDirectory: lastBottle.url.appending(path: "drive_c")) {
            workflow.clearTerminalState()
            startInstall(url, bottle: lastBottle)
        }
    }

    func clearNotice() {
        noticeMessage = nil
        successMessage = nil
    }

    func clearFinishedInstall() {
        guard workflow.state.isTerminal else { return }
        workflow.clearTerminalState()
        lastError = nil
        noticeMessage = nil
        successMessage = nil
    }

    func cancelInstall() {
        guard let bottle = lastBottle, let installID = workflow.installID,
              workflow.beginCancellation(detail: "Stopping Wine processes for this bottle...", for: installID) else {
            return
        }
        installTask?.cancel()
        Task(priority: .userInitiated) {
            do {
                try await Wine.stopBottleProcesses(bottle: bottle, reason: "installer_cancelled")
                await MainActor.run {
                    guard self.workflow.cancel(
                        detail: "Wine processes for this bottle were stopped.", for: installID
                    ) else { return }
                    self.noticeMessage = "Installation cancelled. Wine processes for this bottle were stopped."
                }
            } catch {
                await MainActor.run {
                    guard self.workflow.fail(detail: "Prefix cleanup did not finish.", for: installID) else { return }
                    self.lastError = InstallerErrorInfo(
                        bottleName: bottle.settings.name,
                        installerURL: self.lastInstallerURL ?? bottle.url,
                        message: "Installation was cancelled, but prefix cleanup did not finish: " +
                            error.localizedDescription
                    )
                }
            }
        }
    }

    private func runInstall(_ url: URL, bottle: Bottle, installID: UUID) async {
        do {
            try await attemptDirectInstall(url, bottle: bottle, installID: installID)
            try Task.checkCancellation()
            guard workflow.beginFinalization(detail: "Refreshing app list...", for: installID) else { return }
            try bottle.refreshInstalledPrograms()
            try Task.checkCancellation()
            guard workflow.succeed(detail: "\(url.lastPathComponent) finished.", for: installID) else { return }
            successMessage = "\(url.lastPathComponent) in \(bottle.settings.name) finished."
        } catch is Wine.ProgramLaunchIntentionalTermination {
            // cancelInstall() owns the user-facing completion state for deliberate cleanup.
        } catch is CancellationError {
            // cancelInstall() owns the user-facing completion state for deliberate cleanup.
        } catch {
            guard workflow.installID == installID else { return }
            try? await Wine.stopBottleProcesses(bottle: bottle, reason: "installer_failed")
            guard workflow.fail(detail: "Bourbon tried the normal path and a recovery path.", for: installID) else { return }
            lastError = InstallerErrorInfo(
                bottleName: bottle.settings.name,
                installerURL: url,
                message: error.localizedDescription
            )
        }
    }

    private func attemptDirectInstall(_ url: URL, bottle: Bottle, installID: UUID) async throws {
        update(.analyzingInstaller, detail: "Analyzing \(url.lastPathComponent)...", installID: installID)

        if url.pathExtension.lowercased() == "bat" {
            update(.launchingInstaller, detail: "Launching \(url.lastPathComponent)...", installID: installID)
            try await Wine.runBatchFile(url: url, bottle: bottle)
            return
        }

        do {
            try await Wine.runProgram(at: url, bottle: bottle) { progress in
                Task { @MainActor in
                    switch progress {
                    case .analyzingInstaller:
                        self.update(.analyzingInstaller, detail: "Reading installer metadata...", installID: installID)
                    case .preparingApplication:
                        self.update(.checkingCompatibility, detail: "Checking compatibility...", installID: installID)
                    case .launching:
                        self.update(.waitingForInstaller, detail: "Waiting for installer to finish...", installID: installID)
                    }
                }
            }
        } catch {
            try await attemptExtractedInstallerFallback(url, bottle: bottle, originalError: error, installID: installID)
        }
    }

    private func attemptExtractedInstallerFallback(
        _ url: URL, bottle: Bottle, originalError: Error, installID: UUID
    ) async throws {
        update(activity: .recovering, detail: "Trying another installation method...", installID: installID)
        let candidates = findCandidateExecutables(in: url.deletingLastPathComponent())
        if let candidate = candidates.first {
            update(.waitingForInstaller, detail: "Waiting for \(candidate.lastPathComponent) to finish...", installID: installID)
            try await Wine.runProgram(at: candidate, bottle: bottle)
            return
        }
        throw originalError
    }

    private func findCandidateExecutables(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "exe" }
            .sorted(by: rankCandidateExecutable)
    }

    private func rankCandidateExecutable(_ lhs: URL, _ rhs: URL) -> Bool {
        candidateScore(lhs) > candidateScore(rhs)
    }

    private func candidateScore(_ url: URL) -> Int {
        let name = url.lastPathComponent.lowercased()
        if name == "setup.exe" { return 500 }
        if name == "install.exe" { return 450 }
        if name == "launcher.exe" { return 400 }
        if name == "bootstrap.exe" { return 350 }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return min(size / 1_000_000, 300)
    }

    private func update(_ stage: InstallStage, detail: String, installID: UUID) {
        let activity: InstallerWorkflowActivity
        switch stage {
        case .choosingInstaller:
            activity = .opening
        case .analyzingInstaller:
            activity = .metadata
        case .checkingCompatibility:
            activity = .preparing
        case .launchingInstaller:
            activity = .launching
        case .waitingForInstaller:
            activity = .installing
        case .refreshingAppList:
            activity = .refreshing
        case .cancelling:
            activity = .installing
        case .completed, .cancelled, .failed:
            activity = .done
        }
        update(activity: activity, detail: detail, installID: installID)
    }

    private func update(activity: InstallerWorkflowActivity, detail: String, installID: UUID) {
        _ = workflow.update(activity: activity, detail: detail, for: installID)
    }
}

struct FirstInstallView: View {
    @ObservedObject var bottle: Bottle
    @ObservedObject private var installManager = InstallManager.shared
    let initialInstallerURL: URL?
    let dismiss: () -> Void

    var body: some View {
        BourbonPanelBackdrop {
            ZStack {
                ScrollView {
                    BourbonFloatingPanel(maxWidth: 580) {
                        VStack(spacing: 18) {
                            Text("Install your first app")
                                .font(.largeTitle.bold())
                            Text("Choose a Windows installer to add to this bottle.")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            InstallerPickerCard(
                                title: "Choose File",
                                subtitle: "Drag & Drop or choose a Windows installer.",
                                supportedText: ".exe .msi .bat .zip .rar .7z .iso"
                            ) {
                                if let url = selectInstaller(startingDirectory: bottle.url.appending(path: "drive_c")) {
                                    runInstaller(url)
                                }
                            }

                            Button("Skip for now") {
                                dismiss()
                            }
                            .buttonStyle(BourbonSecondaryButtonStyle())
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 420)
                }

            }
        }
        .onAppear {
            if let initialInstallerURL {
                runInstaller(initialInstallerURL)
            }
        }
        .navigationTitle("Install First App")
    }

    private func runInstaller(_ url: URL) {
        installManager.startInstall(url, bottle: bottle)
        dismiss()
    }

}

struct InstallerPickerCard: View {
    var title: String = "Choose File"
    var subtitle: String = "Drag & Drop or choose a supported installer."
    var supportedText: String = ".exe .msi .bat .zip .rar .7z .iso"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(BourbonStyle.amber)
                Text(title)
                    .font(.title3.bold())
                Text(subtitle)
                    .foregroundStyle(.secondary)
                Text("Supported: \(supportedText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 170)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                    .foregroundStyle(BourbonStyle.amber.opacity(0.65))
            }
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Choose or drop a supported Windows installer.")
    }
}

@MainActor
func selectInstaller(startingDirectory: URL) -> URL? {
    let panel = NSOpenPanel()
    PanelRetainer.shared.retain(panel)
    defer {
        PanelRetainer.shared.release(panel)
    }
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowedContentTypes = bourbonInstallerContentTypes()
    panel.directoryURL = startingDirectory
    return panel.runModal() == .OK ? panel.urls.first : nil
}

@MainActor
private final class PanelRetainer {
    static let shared = PanelRetainer()
    private var panels: [NSOpenPanel] = []

    func retain(_ panel: NSOpenPanel) {
        panels.append(panel)
    }

    func release(_ panel: NSOpenPanel) {
        panels.removeAll { $0 === panel }
    }
}

func bourbonInstallerContentTypes() -> [UTType] {
    [
        UTType.exe,
        UTType(exportedAs: "com.microsoft.msi-installer"),
        UTType(exportedAs: "com.microsoft.bat"),
        UTType(filenameExtension: "zip"),
        UTType(filenameExtension: "rar"),
        UTType(filenameExtension: "7z"),
        UTType(filenameExtension: "iso")
    ].compactMap { $0 }
}

struct InstallerPipelineStep: Identifiable {
    enum State {
        case waiting
        case active
        case complete
    }

    enum Kind: Int, CaseIterable {
        case opening
        case looking
        case metadata
        case architecture
        case searching
        case preparing
        case launching
        case installing
        case recovering
        case refreshing
        case done

        var title: String {
            switch self {
            case .opening:
                return "Opening installer..."
            case .looking:
                return "Looking at installer..."
            case .metadata:
                return "Reading metadata..."
            case .architecture:
                return "Checking architecture..."
            case .searching:
                return "Searching for executable..."
            case .preparing:
                return "Preparing environment..."
            case .launching:
                return "Launching installer..."
            case .installing:
                return "Installing..."
            case .recovering:
                return "Trying another installation method..."
            case .refreshing:
                return "Refreshing installed applications..."
            case .done:
                return "Done."
            }
        }

        var order: Int { rawValue }
    }

    let id = UUID()
    let kind: Kind
    let state: State

    static func makeSteps(for workflow: InstallerWorkflow) -> [InstallerPipelineStep] {
        let activeKind: Kind? = switch workflow.activity {
        case .opening: .opening
        case .looking: .looking
        case .metadata: .metadata
        case .architecture: .architecture
        case .searching: .searching
        case .preparing: .preparing
        case .launching: .launching
        case .installing: .installing
        case .recovering: .recovering
        case .refreshing: .refreshing
        case .done: .done
        }

        return Kind.allCases.map { kind in
            let state: State
            if workflow.state == .succeeded || workflow.activity == .done {
                state = .complete
            } else if kind.order < (activeKind?.order ?? 0) {
                state = .complete
            } else if kind == activeKind, workflow.state.isActive {
                state = .active
            } else {
                state = .waiting
            }
            return InstallerPipelineStep(kind: kind, state: state)
        }
    }

    func waiting() -> InstallerPipelineStep {
        InstallerPipelineStep(kind: kind, state: .waiting)
    }

    func active() -> InstallerPipelineStep {
        InstallerPipelineStep(kind: kind, state: .active)
    }

    func completed() -> InstallerPipelineStep {
        InstallerPipelineStep(kind: kind, state: .complete)
    }
}

struct InstallerProgressCard: View {
    let status: String
    let steps: [InstallerPipelineStep]
    @ObservedObject private var installManager = InstallManager.shared

    var body: some View {
        BourbonGlassCard(maxWidth: 420) {
            VStack(alignment: .leading, spacing: 16) {
                if installManager.workflow.showsSpinner {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }
                Text(status)
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(steps) { step in
                        HStack(spacing: 10) {
                            pipelineIcon(for: step.state)
                            Text(step.kind.title)
                                .foregroundStyle(step.state == .waiting ? .secondary : .primary)
                            Spacer()
                        }
                        .font(.caption)
                    }
                }

                Text("Follow any prompts in the Windows installer when they appear.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                if installManager.canCancel {
                    Button("Cancel Installer") {
                        installManager.cancelInstall()
                    }
                    .buttonStyle(BourbonSecondaryButtonStyle())
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func pipelineIcon(for state: InstallerPipelineStep.State) -> some View {
        switch state {
        case .waiting:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .active:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 12, height: 12)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(BourbonStyle.amber)
        }
    }
}

struct InstallerErrorCard: View {
    let error: InstallerErrorInfo
    let tryAgain: () -> Void
    let cancel: () -> Void
    let reportIssue: () -> Void

    var body: some View {
        BourbonGlassCard(maxWidth: 460) {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(BourbonStyle.amber)

                Text("Installation couldn’t be completed.")
                    .font(.title2.bold())

                Text(
                    "Bourbon tried the normal installation path and a recovery path. " +
                    "You can try again or report the issue with diagnostic details."
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack {
                    Button("Try Again", action: tryAgain)
                        .buttonStyle(BourbonPrimaryButtonStyle())
                        .help("Run the same installer again.")

                    Button("Report Issue", action: reportIssue)
                        .buttonStyle(BourbonSecondaryButtonStyle())
                        .help("Prepare a troubleshooting report.")

                    Button("Cancel", action: cancel)
                        .buttonStyle(BourbonSecondaryButtonStyle())
                        .help("Close this message.")
                }
            }
        }
    }
}

struct InstallerErrorInfo: Identifiable {
    let id = UUID()
    let bottleName: String
    let installerURL: URL
    let message: String
}

import AppKit
import Darwin
import SwiftUI
import WhiskyKit

// swiftlint:disable file_length

enum BourbonReportType: String, CaseIterable, Codable, Identifiable {
    case crash = "Crash"
    case bug = "Bug"
    case error = "Error"
    case installIssue = "Install Issue"
    case updateIssue = "Update Issue"
    case runtimeIssue = "Runtime Issue"
    case other = "Other"

    var id: String { rawValue }
}

struct BourbonReportDraft: Identifiable {
    let id = UUID()
    var reportType: BourbonReportType
    var title: String
    var description: String
    var stepsToReproduce: String
    var expectedBehavior: String
    var actualBehavior: String
    var contactEmail: String
    var includeDiagnostics = true
    var includeLogs = true
    var recentErrorMessage: String?
    var crashLog: String?

    static let blank = BourbonReportDraft(
        reportType: .bug,
        title: "",
        description: "",
        stepsToReproduce: "",
        expectedBehavior: "",
        actualBehavior: "",
        contactEmail: "",
        recentErrorMessage: nil,
        crashLog: nil
    )
}

struct BourbonSubmittedReport: Codable, Identifiable {
    let id: UUID
    let reportType: String
    let title: String
    let description: String
    let stepsToReproduce: String
    let expectedBehavior: String
    let actualBehavior: String
    let contactEmail: String?
    let diagnostics: [String: String]
    let logs: String?
    let appVersion: String
    let buildNumber: String
    let licenseId: String?
    let timestamp: String
}

@MainActor
enum BourbonReportCenter {
    private static let reportNotification = Notification.Name("BourbonOpenProblemReport")
    private static var notificationObserver: NSObjectProtocol?
    private static var reportWindows: [NSWindow] = []

    static func startListeningForReportRequests() {
        guard notificationObserver == nil else { return }
        notificationObserver = NotificationCenter.default.addObserver(
            forName: reportNotification,
            object: nil,
            queue: .main
        ) { notification in
            let title = notification.userInfo?["title"] as? String ?? "Bourbon runtime error"
            let message = notification.userInfo?["message"] as? String ?? ""
            Task { @MainActor in
                openRuntimeReport(title: title, errorMessage: message)
            }
        }
    }

    static func requestRuntimeReport(title: String, message: String) {
        NotificationCenter.default.post(
            name: reportNotification,
            object: nil,
            userInfo: ["title": title, "message": message]
        )
    }

    static func openReport(_ draft: BourbonReportDraft = .blank) {
        let controller = NSHostingController(rootView: BourbonReportView(initialDraft: draft))
        let window = NSWindow(contentViewController: controller)
        window.title = "Report a Problem"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 880, height: 780))
        window.center()
        window.isReleasedWhenClosed = false
        reportWindows.append(window)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { notification in
            guard let closedWindow = notification.object as? NSWindow else { return }
            Task { @MainActor in
                reportWindows.removeAll { $0 === closedWindow }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    static func openInstallerReport(bottleName: String, installerURL: URL, errorMessage: String) {
        openReport(BourbonReportDraft(
            reportType: .installIssue,
            title: "Install failed for \(installerURL.lastPathComponent)",
            description: errorMessage,
            stepsToReproduce: "Install \(installerURL.lastPathComponent) into \(bottleName).",
            expectedBehavior: "The installer should open and complete normally.",
            actualBehavior: errorMessage,
            contactEmail: "",
            recentErrorMessage: errorMessage,
            crashLog: nil
        ))
    }

    static func openRuntimeReport(title: String, errorMessage: String) {
        openReport(BourbonReportDraft(
            reportType: .runtimeIssue,
            title: title,
            description: errorMessage,
            stepsToReproduce: "",
            expectedBehavior: "The Windows app should launch normally.",
            actualBehavior: errorMessage,
            contactEmail: "",
            recentErrorMessage: errorMessage,
            crashLog: nil
        ))
    }

    static func openUpdateReport(_ error: Error) {
        openReport(BourbonReportDraft(
            reportType: .updateIssue,
            title: "Bourbon update failed",
            description: error.localizedDescription,
            stepsToReproduce: "Check for Bourbon updates.",
            expectedBehavior: "Bourbon should check for and install updates normally.",
            actualBehavior: error.localizedDescription,
            contactEmail: "",
            recentErrorMessage: error.localizedDescription,
            crashLog: nil
        ))
    }

    @MainActor
    static func promptForRecentCrashIfNeeded() {
        guard let crash = BourbonCrashDetector.recentUnpromptedCrash() else { return }

        let alert = NSAlert()
        alert.messageText = "Bourbon closed unexpectedly."
        alert.informativeText = "Send a crash report? You can review everything before it is sent."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Send Report")
        alert.addButton(withTitle: "View Report")
        alert.addButton(withTitle: "Don’t Send")

        let response = alert.runModal()
        BourbonCrashDetector.markPrompted(crash)
        guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn else { return }

        openReport(BourbonReportDraft(
            reportType: .crash,
            title: "Bourbon closed unexpectedly",
            description: "Bourbon appears to have closed unexpectedly.",
            stepsToReproduce: "",
            expectedBehavior: "Bourbon should remain open.",
            actualBehavior: "Bourbon closed unexpectedly.",
            contactEmail: "",
            recentErrorMessage: "Detected recent crash log: \(crash.url.lastPathComponent)",
            crashLog: crash.contents
        ))
    }
}

struct BourbonReportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: BourbonReportDraft
    @State private var reviewPayload: BourbonSubmittedReport?
    @State private var submissionState: SubmissionState = .editing
    @State private var statusMessage: String?

    init(initialDraft: BourbonReportDraft) {
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        BourbonPanelBackdrop {
            BourbonFloatingPanel(maxWidth: 760) {
                VStack(spacing: 0) {
                    header

                    Divider()

                    if let reviewPayload {
                        reviewView(report: reviewPayload)
                    } else {
                        formView
                    }
                }
                .frame(minWidth: 640, minHeight: 580)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Report a Problem")
                    .font(.title2.bold())
                Text("Bourbon never sends reports silently. Review the payload before submitting.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if BourbonReportStore.pendingCount > 0 {
                Button("Retry Pending") {
                    Task { await retryPending() }
                }
            }
        }
        .padding(20)
    }

    private var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Report type", selection: $draft.reportType) {
                    ForEach(BourbonReportType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                TextField("Title", text: $draft.title)

                reportEditor("What happened?", text: $draft.description)
                reportEditor("Steps to reproduce", text: $draft.stepsToReproduce)
                reportEditor("Expected behavior", text: $draft.expectedBehavior)
                reportEditor("Actual behavior", text: $draft.actualBehavior)

                TextField("Optional contact email", text: $draft.contactEmail)

                Toggle("Include diagnostics", isOn: $draft.includeDiagnostics)
                Toggle("Include logs", isOn: $draft.includeLogs)

                if let statusMessage {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    Button("View Report") {
                        reviewPayload = BourbonReportBuilder.makeReport(from: draft)
                    }
                    .buttonStyle(BourbonPrimaryButtonStyle())
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
        }
    }

    private func reviewView(report: BourbonSubmittedReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review Report")
                .font(.title3.bold())

            Text(reportPreview(report))
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))

            if let statusMessage {
                Text(statusMessage)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Back") {
                    reviewPayload = nil
                    statusMessage = nil
                }

                Spacer()

                Button(submissionState == .submitting ? "Submitting..." : "Submit Report") {
                    Task { await submit(report) }
                }
                .buttonStyle(BourbonPrimaryButtonStyle())
                .disabled(submissionState == .submitting)
            }
        }
        .padding(20)
    }

    private func reportEditor(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            TextEditor(text: text)
                .frame(minHeight: 70)
                .scrollContentBackground(.hidden)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func submit(_ report: BourbonSubmittedReport) async {
        submissionState = .submitting
        do {
            let reportID = try await BourbonReportClient.submit(report)
            await MainActor.run {
                submissionState = .submitted
                statusMessage = "Thanks. Your report was submitted.\nReport ID: \(reportID)"
            }
        } catch {
            BourbonReportStore.savePending(report)
            await MainActor.run {
                submissionState = .savedPending
                statusMessage = """
                Bourbon could not reach the report server. Your report was saved locally and can be retried later.
                """
            }
        }
    }

    private func retryPending() async {
        let result = await BourbonReportStore.retryPending()
        await MainActor.run {
            statusMessage = "Retried pending reports. Sent: \(result.sent). Still pending: \(result.remaining)."
        }
    }

    private func reportPreview(_ report: BourbonSubmittedReport) -> String {
        let encoded = try? JSONEncoder.pretty.encode(report)
        return encoded.flatMap { String(data: $0, encoding: .utf8) } ?? "Unable to preview report."
    }

    enum SubmissionState {
        case editing
        case submitting
        case submitted
        case savedPending
    }
}

enum BourbonReportBuilder {
    static func makeReport(from draft: BourbonReportDraft) -> BourbonSubmittedReport {
        let diagnostics = draft.includeDiagnostics ? BourbonDiagnosticsCollector.diagnostics(
            recentError: draft.recentErrorMessage,
            crashLog: draft.crashLog
        ) : [:]
        let logs = draft.includeLogs ? BourbonDiagnosticsCollector.recentLogs() : nil
        let build = BourbonBuildDiagnostics.current
        let contact = draft.contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let license = LicenseKeychainStore.currentLicense()?.publicLicenseId

        return BourbonSubmittedReport(
            id: UUID(),
            reportType: draft.reportType.rawValue,
            title: BourbonRedactor.redact(draft.title, allowEmail: !contact.isEmpty),
            description: BourbonRedactor.redact(draft.description, allowEmail: !contact.isEmpty),
            stepsToReproduce: BourbonRedactor.redact(draft.stepsToReproduce, allowEmail: !contact.isEmpty),
            expectedBehavior: BourbonRedactor.redact(draft.expectedBehavior, allowEmail: !contact.isEmpty),
            actualBehavior: BourbonRedactor.redact(draft.actualBehavior, allowEmail: !contact.isEmpty),
            contactEmail: contact.isEmpty ? nil : contact,
            diagnostics: diagnostics,
            logs: logs,
            appVersion: build.version,
            buildNumber: build.buildNumber,
            licenseId: license,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }
}

enum BourbonDiagnosticsCollector {
    static func diagnostics(recentError: String?, crashLog: String?) -> [String: String] {
        let build = BourbonBuildDiagnostics.current
        let process = ProcessInfo.processInfo

        let runtimeVersion = WhiskyWineInstaller.whiskyWineVersion().map(String.init(describing:)) ?? "Not installed"

        var values: [String: String] = [
            "Bourbon version": build.version,
            "Build number": build.buildNumber,
            "Git commit": build.gitCommitShort,
            "Build date": build.buildDateUTC,
            "macOS version": process.operatingSystemVersionString,
            "Mac model": macModel(),
            "CPU architecture": architecture(),
            "Update feed URL": build.updateFeedURL,
            "BourbonWine runtime version": runtimeVersion
        ]

        if let recentError {
            values["Recent error"] = BourbonRedactor.redact(recentError)
        }

        if let crashLog {
            values["Crash log"] = BourbonRedactor.redact(String(crashLog.prefix(12_000)))
        }

        return values
    }

    static func recentLogs() -> String? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: Wine.logsFolder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let logs = urls
            .filter { $0.pathExtension == "log" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return lhsDate > rhsDate
            }
            .prefix(3)
            .compactMap { url -> String? in
                guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return "--- \(url.lastPathComponent) ---\n\(String(contents.suffix(4_000)))"
            }
            .joined(separator: "\n\n")

        return logs.isEmpty ? nil : BourbonRedactor.redact(logs)
    }

    private static func architecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static func macModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}

enum BourbonRedactor {
    static func redact(_ value: String, allowEmail: Bool = false) -> String {
        var redacted = value
        let sensitivePattern = #"(token|api[_-]?key|secret|password|licenseToken|privateLicenseToken)"#
            + #"["'\s:=]+[A-Za-z0-9._\-+/=]{8,}"#
        let home = NSHomeDirectory()
        redacted = redacted.replacingOccurrences(of: home, with: "~")

        if !allowEmail {
            redacted = replace(
                pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
                in: redacted,
                with: "[redacted-email]",
                options: [.caseInsensitive]
            )
        }

        redacted = replace(
            pattern: sensitivePattern,
            in: redacted,
            with: "$1=[redacted]",
            options: [.caseInsensitive]
        )

        redacted = replace(
            pattern: #"BRBN-[A-Za-z0-9\-]{12,}"#,
            in: redacted,
            with: "[redacted-license-token]"
        )

        return redacted
    }

    private static func replace(
        pattern: String,
        in value: String,
        with template: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.stringByReplacingMatches(in: value, options: [], range: range, withTemplate: template)
    }
}

enum BourbonReportClient {
    static func submit(_ report: BourbonSubmittedReport) async throws -> String {
        guard let url = URL(string: "https://api.getbourbon.app/reports/bug") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(report)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(ReportResponse.self, from: data)
        return decoded.reportId
    }

    private struct ReportResponse: Decodable {
        let reportId: String
    }
}

enum BourbonReportStore {
    struct RetryResult {
        let sent: Int
        let remaining: Int
    }

    static var pendingCount: Int {
        pendingReportURLs().count
    }

    static func savePending(_ report: BourbonSubmittedReport) {
        do {
            try FileManager.default.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)
            let url = pendingDirectory.appendingPathComponent("\(report.id.uuidString).json")
            try JSONEncoder.pretty.encode(report).write(to: url)
        } catch {
            print("Failed to save pending report: \(error)")
        }
    }

    static func retryPending() async -> RetryResult {
        var sent = 0

        for url in pendingReportURLs() {
            guard let data = try? Data(contentsOf: url),
                  let report = try? JSONDecoder().decode(BourbonSubmittedReport.self, from: data) else {
                continue
            }

            do {
                _ = try await BourbonReportClient.submit(report)
                try? FileManager.default.removeItem(at: url)
                sent += 1
            } catch {
                continue
            }
        }

        return RetryResult(sent: sent, remaining: pendingReportURLs().count)
    }

    private static var pendingDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Bourbon/PendingReports", isDirectory: true)
    }

    private static func pendingReportURLs() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: pendingDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
    }
}

struct BourbonCrashReport {
    let url: URL
    let contents: String
}

enum BourbonCrashDetector {
    private static let promptedCrashKey = "bourbon.promptedCrashReports"

    static func recentUnpromptedCrash() -> BourbonCrashReport? {
        let directories = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/DiagnosticReports"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/CrashReporter")
        ]
        let prompted = Set(UserDefaults.standard.stringArray(forKey: promptedCrashKey) ?? [])
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)

        let candidates = directories.flatMap { directory -> [URL] in
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        }

        for url in candidates
            where url.lastPathComponent.localizedCaseInsensitiveContains("Bourbon") ||
            url.lastPathComponent.localizedCaseInsensitiveContains("Whisky") {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            guard modified > cutoff, !prompted.contains(url.lastPathComponent) else { continue }
            let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return BourbonCrashReport(url: url, contents: contents)
        }

        return nil
    }

    static func markPrompted(_ report: BourbonCrashReport) {
        var prompted = UserDefaults.standard.stringArray(forKey: promptedCrashKey) ?? []
        prompted.append(report.url.lastPathComponent)
        UserDefaults.standard.set(Array(prompted.suffix(25)), forKey: promptedCrashKey)
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

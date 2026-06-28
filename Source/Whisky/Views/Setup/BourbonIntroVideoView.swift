import AVKit
import Security
import SwiftUI

struct BourbonIntroVideoView: View {
    let buttonTitle: String
    let onFinished: () -> Void

    @State private var player: AVPlayer?
    @State private var showButton = false
    @State private var showAdminUnlock = false
    @State private var adminUnlockTriggered = false
    @State private var playbackObserver: NSObjectProtocol?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            if let player {
                PlayerContainerView(player: player)
                    .ignoresSafeArea()
            }

            Button(buttonTitle) {
                if adminUnlockTriggered {
                    adminUnlockTriggered = false
                    return
                }
                finishIntro()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(.white.opacity(0.28), in: Capsule())
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(.white)
            .overlay(
                Capsule()
                    .stroke(.white.opacity(0.35), lineWidth: 1)
            )
            .controlSize(.large)
            .padding(.bottom, 0)
            .opacity(showButton ? 1 : 0)
            .allowsHitTesting(showButton)
            .animation(.easeOut(duration: 0.6), value: showButton)
            .onLongPressGesture(minimumDuration: 5) {
                adminUnlockTriggered = true
                showAdminUnlock = true
            }
        }
        .sheet(isPresented: $showAdminUnlock) {
            AdminUnlockView()
        }
        .onAppear {
            guard player == nil else { return }

            guard let url = Bundle.main.url(forResource: "BourbonIntro", withExtension: "mov") else {
                finishIntro()
                return
            }

            let player = AVPlayer(url: url)
            self.player = player
            player.play()

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

    private func finishIntro() {
        cleanupPlayer()
        onFinished()
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

struct AdminUnlockView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var licenseID = ""
    @State private var password = ""
    @State private var isUnlocking = false
    @State private var unlockFailed = false

    var body: some View {
        BourbonBackground {
            BourbonGlassCard(maxWidth: 420) {
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
        }
        .frame(width: 520, height: 360)
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
                    isUnlocking = false
                    dismiss()
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

    private static var baseURL: URL {
        if let configuredURL = localConfigURL {
            return configuredURL
        }

        if let environmentURL = ProcessInfo.processInfo.environment["BOURBON_ADMIN_API_BASE_URL"],
           let url = URL(string: environmentURL) {
            return url
        }

        return URL(string: "https://api.bourbon.app")!
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
        view.videoGravity = .resize
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

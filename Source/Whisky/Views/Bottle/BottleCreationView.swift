//
//  BottleCreationView.swift
//  Whisky
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit

struct BottleCreationView: View {
    @Binding var newlyCreatedBottleURL: URL?
    @Binding var selectedInstallerURL: URL?
    var cancel: () -> Void = {}
    var created: (URL) -> Void = { _ in }

    private let supportedWindowsVersions: [WinVersion] = [.win11, .win10, .win81, .win8, .win7, .winXP]
    private let deprecatedWindowsVersions: Set<WinVersion> = [.win7, .winXP]

    @State private var newBottleName: String = ""
    @State private var newBottleVersion: WinVersion = .win10
    @State private var bottleType: BourbonBottleType = .applications
    @State private var isCreating = false
    @State private var creationError: String?
    @State private var creationTask: Task<Void, Never>?
    @State private var newBottleURL: URL = UserDefaults.standard.url(forKey: "defaultBottleLocation")
                                           ?? BottleData.defaultBottleDir

    var body: some View {
        BourbonPanelBackdrop {
            BourbonFloatingPanel(maxWidth: 920) {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            headerSection
                            bottleDetailsSection
                            installerSection
                            storageSection
                        }
                        .frame(maxWidth: 860, alignment: .leading)
                        .padding(.bottom, 22)
                    }

                    actionBar
                }
                .frame(maxHeight: 760)
            }
        }
        .navigationTitle("Create Bottle")
        .onSubmit {
            if canCreate {
                submit()
            }
        }
        .onDisappear {
            creationTask?.cancel()
            creationTask = nil
        }
    }

    func submit() {
        guard canCreate else { return }

        let bottleName = newBottleName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = bottleName.isEmpty ? "My Bottle" : bottleName
        guard !isCreating else { return }
        creationError = nil
        isCreating = true
        print("bottle.creation.started")
        creationTask = Task { @MainActor in
            defer {
                isCreating = false
                creationTask = nil
            }

            do {
                let url = try await BottleVM.shared.createNewBottle(
                    bottleName: finalName,
                    winVersion: newBottleVersion,
                    bottleURL: newBottleURL
                )
                newlyCreatedBottleURL = url
                creationTask = nil
                created(url)
                cancel()
            } catch is CancellationError {
                print("bottle.creation.cancelled")
                creationError = "Bottle creation was cancelled."
            } catch {
                print("bottle.creation.failed")
                creationError = Task.isCancelled
                    ? "Bottle creation was cancelled."
                    : "Bourbon couldn’t create this bottle. Try again."
            }
        }
    }

    private var canCreate: Bool {
        !isCreating
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Create Bottle")
                .font(.largeTitle.bold())
            Text("Set up a private Windows environment for your app or game.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var bottleDetailsSection: some View {
        BourbonGlassCard(maxWidth: 820) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Bottle setup")
                    .font(.title2.bold())

                TextField("Bottle Name (optional)", text: $newBottleName)
                    .textFieldStyle(.roundedBorder)
                    .help("Name this bottle after the app or game you plan to install.")

                Text(bottleNameHelperText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Bottle Type", selection: $bottleType) {
                    ForEach(BourbonBottleType.allCases) { type in
                        Label(type.title, systemImage: type.systemImage)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .help("Choose a simple starting profile for this bottle.")

                Picker("Windows version", selection: $newBottleVersion) {
                    ForEach(supportedWindowsVersions, id: \.self) { version in
                        Text(versionTitle(version))
                            .tag(version)
                    }
                }
                .help("Choose the Windows version this app should see.")

                if deprecatedWindowsVersions.contains(newBottleVersion) {
                    Text("This Windows version is deprecated. Some apps may not work correctly.")
                        .font(.caption)
                        .foregroundStyle(BourbonStyle.amber)
                }
            }
        }
    }

    private var installerSection: some View {
        BourbonGlassCard(maxWidth: 820) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Choose your installer")
                    .font(.title2.bold())
                Text("Pick the Windows installer you want to use after this bottle is created.")
                    .foregroundStyle(.secondary)

                InstallerPickerCard(
                    title: selectedInstallerURL?.lastPathComponent ?? "Choose File",
                    subtitle: "Drag & Drop or choose a supported installer.",
                    supportedText: ".exe .msi .bat .zip .rar .7z .iso"
                ) {
                    if let url = selectInstaller(startingDirectory: newBottleURL) {
                        selectedInstallerURL = url
                        if newBottleName.isEmpty {
                            newBottleName = defaultBottleName(for: url)
                        }
                    }
                }
            }
        }
    }

    private var storageSection: some View {
        BourbonGlassCard(maxWidth: 820) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Storage")
                    .font(.title2.bold())
                Text("Bourbon will keep this bottle in your selected storage folder.")
                    .foregroundStyle(.secondary)

                Button {
                    browseBottleLocation()
                } label: {
                    HStack {
                        Label(storageLocationLabel, systemImage: "folder")
                            .lineLimit(1)
                        Spacer()
                        Text("Change")
                            .foregroundStyle(BourbonStyle.amber)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(BourbonSecondaryButtonStyle())
                .help("Choose where this bottle will be stored.")
            }
        }
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(isCreating ? "Cancel Creation" : "Cancel") {
                    creationTask?.cancel()
                    cancel()
                }
                .buttonStyle(BourbonSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
                .help("Close without creating a bottle.")

                Spacer()

                Button(isCreating ? "Creating…" : "Create") {
                    submit()
                }
                .buttonStyle(BourbonPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate || isCreating)
                .help("Create a new Windows environment.")
            }

            if let creationError {
                Text(creationError)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 18)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var bottleNameHelperText: String {
        let name = newBottleName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return "Leave this blank and Bourbon will create \"My Bottle\" for you."
        }
        return "Ready to create \"\(name)\""
    }

    private var storageLocationLabel: String {
        if newBottleURL == BottleData.defaultBottleDir {
            return "Default Bourbon location"
        }

        return "Custom location selected"
    }

    private func versionTitle(_ version: WinVersion) -> String {
        if deprecatedWindowsVersions.contains(version) {
            return "\(version.pretty()) (deprecated)"
        }
        return version.pretty()
    }

    private func browseBottleLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = BottleData.containerDir
        panel.begin { result in
            if result == .OK, let url = panel.urls.first {
                newBottleURL = url
            }
        }
    }

    private func defaultBottleName(for url: URL) -> String {
        url.deletingPathExtension()
            .lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}

enum BourbonBottleType: String, CaseIterable, Identifiable {
    case gaming
    case applications
    case development
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gaming:
            return "Gaming"
        case .applications:
            return "Applications"
        case .development:
            return "Development"
        case .advanced:
            return "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .gaming:
            return "gamecontroller"
        case .applications:
            return "app"
        case .development:
            return "hammer"
        case .advanced:
            return "slider.horizontal.3"
        }
    }
}

#Preview {
    BottleCreationView(newlyCreatedBottleURL: .constant(nil), selectedInstallerURL: .constant(nil))
}

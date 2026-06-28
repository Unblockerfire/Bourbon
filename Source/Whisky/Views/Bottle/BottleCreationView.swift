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

    private let supportedWindowsVersions: [WinVersion] = [.win11, .win10, .win81, .win8, .win7, .winXP]
    private let deprecatedWindowsVersions: Set<WinVersion> = [.win7, .winXP]

    @State private var newBottleName: String = ""
    @State private var newBottleVersion: WinVersion = .win10
    @State private var bottleType: BourbonBottleType = .applications
    @State private var newBottleURL: URL = UserDefaults.standard.url(forKey: "defaultBottleLocation")
                                           ?? BottleData.defaultBottleDir
    @State private var missingDependencies: [Wine.RuntimeDependency] = Wine
        .missingRuntimeDependencies(requiredOnly: false)

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BourbonBackground {
                BourbonGlassCard(maxWidth: 520) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Create Bottle")
                                .font(.largeTitle.bold())
                            Text("Set up a private Windows environment for this app.")
                            .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 12) {
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
                        .padding(16)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Choose your installer.")
                                .font(.headline)

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

                        Button {
                            browseBottleLocation()
                        } label: {
                            Label(newBottleURL.prettyPath(), systemImage: "folder")
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(BourbonSecondaryButtonStyle())
                        .help("Choose where this bottle will be stored.")

                        if !missingDependencies.isEmpty {
                            runtimeDependencySection
                        }

                        HStack {
                            Button("Cancel") {
                                dismiss()
                            }
                            .buttonStyle(BourbonSecondaryButtonStyle())
                            .keyboardShortcut(.cancelAction)

                            Spacer()

                            Button("Create Bottle") {
                                submit()
                            }
                            .buttonStyle(BourbonPrimaryButtonStyle())
                            .keyboardShortcut(.defaultAction)
                            .disabled(hasMissingRequiredDependencies)
                            .help("Create a new Windows environment.")
                        }
                    }
                }
            }
            .onSubmit {
                if !hasMissingRequiredDependencies {
                    submit()
                }
            }
            .onAppear {
                missingDependencies = Wine.missingRuntimeDependencies(requiredOnly: false)
            }
        }
        .frame(width: 720, height: 680)
    }

    func submit() {
        let bottleName = newBottleName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = bottleName.isEmpty ? "My Bottle" : bottleName
        newlyCreatedBottleURL = BottleVM.shared.createNewBottle(
            bottleName: finalName,
            winVersion: newBottleVersion,
            bottleURL: newBottleURL
        )
        dismiss()
    }

    private var hasMissingRequiredDependencies: Bool {
        missingDependencies.contains(where: \.required)
    }

    private var bottleNameHelperText: String {
        let name = newBottleName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return "Leave this blank and Bourbon will create \"My Bottle\" for you."
        }
        return "Ready to create \"\(name)\""
    }

    private var runtimeDependencyFooter: String {
        if hasMissingRequiredDependencies {
            return "Bottle creation is blocked until required Bourbon runtime dependencies are available."
        }
        return "These optional Bourbon runtime dependencies are not currently bundled. Bottle creation can continue."
    }

    private func versionTitle(_ version: WinVersion) -> String {
        if deprecatedWindowsVersions.contains(version) {
            return "\(version.pretty()) (deprecated)"
        }
        return version.pretty()
    }

    private var runtimeDependencySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Runtime notes")
                .font(.headline)
            ForEach(missingDependencies) { dependency in
                VStack(alignment: .leading, spacing: 4) {
                    Text(dependency.displayName)
                        .font(.subheadline.bold())
                    Text(dependency.required ? "Required" : "Optional")
                        .font(.caption)
                        .foregroundStyle(dependency.required ? .red : .secondary)
                    Text(dependency.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(dependency.installHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Text(runtimeDependencyFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Re-check") {
                missingDependencies = Wine.missingRuntimeDependencies(requiredOnly: false)
            }
            .buttonStyle(BourbonSecondaryButtonStyle())
        }
        .padding(16)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

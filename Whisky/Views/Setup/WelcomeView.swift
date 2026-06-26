//
//  WelcomeView.swift
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
import WhiskyKit

struct WelcomeView: View {
    @State var rosettaInstalled: Bool?
    @State var whiskyWineInstalled: Bool?
    @State var shouldCheckInstallStatus: Bool = false
    @State private var showManualSetup = false
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool
    @Binding var showBottleCreation: Bool
    @AppStorage("hasCompletedFirstRunOnboarding") private var hasCompletedFirstRunOnboarding = false
    var firstTime: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                if firstTime {
                    Text("Welcome to Whisky")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Wine, but a little stronger.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Setup check")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Whisky needs a few tools to run Windows apps correctly.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Setup check")
                .font(.headline)
            Text("Whisky uses separate bottles for Windows apps, plus Rosetta and WhiskyWine to run them on your Mac.")
                .foregroundStyle(.secondary)

            Form {
                InstallStatusView(isInstalled: $rosettaInstalled,
                                  shouldCheckInstallStatus: $shouldCheckInstallStatus,
                                  name: "Rosetta")
                InstallStatusView(isInstalled: $whiskyWineInstalled,
                                  shouldCheckInstallStatus: $shouldCheckInstallStatus,
                                  showUninstall: true,
                                  name: "WhiskyWine")
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .onAppear {
                checkInstallStatus()
            }
            .onChange(of: shouldCheckInstallStatus) {
                checkInstallStatus()
            }

            if showManualSetup {
                ManualSetupView(rosettaInstalled: rosettaInstalled, whiskyWineInstalled: whiskyWineInstalled)
            }

            HStack {
                Button(firstTime ? "Skip for now" : "Close") {
                    if firstTime {
                        hasCompletedFirstRunOnboarding = true
                    }
                    showSetup = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Let me do it manually") {
                    showManualSetup.toggle()
                }

                Button(primaryButtonTitle) {
                    handlePrimaryAction()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 440)
    }

    func checkInstallStatus() {
        rosettaInstalled = Rosetta2.isRosettaInstalled
        whiskyWineInstalled = WhiskyWineInstaller.isWhiskyWineInstalled()
    }

    private var primaryButtonTitle: String {
        if dependenciesInstalled {
            return firstTime ? "Create your first bottle" : "Done"
        }
        return "Install for me"
    }

    private var dependenciesInstalled: Bool {
        rosettaInstalled == true && whiskyWineInstalled == true
    }

    private func handlePrimaryAction() {
        if rosettaInstalled != true {
            path.append(.rosetta)
            return
        }

        if whiskyWineInstalled != true {
            path.append(.whiskyWineDownload)
            return
        }

        hasCompletedFirstRunOnboarding = true
        showSetup = false

        if firstTime {
            showBottleCreation = true
        }
    }
}

struct ManualSetupView: View {
    let rosettaInstalled: Bool?
    let whiskyWineInstalled: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if rosettaInstalled != true {
                ManualDependencyView(
                    name: "Rosetta",
                    reason: "Rosetta lets Whisky run Intel Wine tools on Apple silicon Macs.",
                    command: "/usr/sbin/softwareupdate --install-rosetta --agree-to-license"
                )
            }

            if whiskyWineInstalled != true {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WhiskyWine")
                        .font(.headline)
                    Text("WhiskyWine is the Wine runtime Whisky uses to run Windows apps.")
                        .foregroundStyle(.secondary)
                    Text(
                        "Use Install for me to download the supported runtime, " +
                        "or install a compatible local archive from the next screen."
                    )
                        .foregroundStyle(.secondary)
                }
            }

            Text(
                "Whisky may not work without required setup items. " +
                "Windows apps may fail to open or bottles may not finish creating."
            )
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ManualDependencyView: View {
    let name: String
    let reason: String
    let command: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.headline)
            Text(reason)
                .foregroundStyle(.secondary)
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            HStack {
                Button("Copy command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
                Button("Open Terminal") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                }
            }
        }
    }
}

struct InstallStatusView: View {
    @Binding var isInstalled: Bool?
    @Binding var shouldCheckInstallStatus: Bool
    @State var showUninstall: Bool = false
    @State var name: String
    @State var text: String = String(localized: "setup.install.checking")

    var body: some View {
        HStack {
            Group {
                if let installed = isInstalled {
                    Circle()
                        .foregroundColor(installed ? .green : .red)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: 10)
            Text(String.init(format: text, name))
            Spacer()
            if let installed = isInstalled {
                if installed && showUninstall {
                    Button("setup.uninstall") {
                        uninstall()
                    }
                }
            }
        }
        .onChange(of: isInstalled) {
            if let installed = isInstalled {
                if installed {
                    text = String(localized: "setup.install.installed")
                } else {
                    text = String(localized: "setup.install.notInstalled")
                }
            } else {
                text = String(localized: "setup.install.checking")
            }
        }
    }

    func uninstall() {
        if name == "WhiskyWine" {
            WhiskyWineInstaller.uninstall()
        }

        shouldCheckInstallStatus.toggle()
    }
}

//
//  BottleView.swift
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

enum BottleStage {
    case config
    case programs
    case processes
}

struct BottleView: View {
    @ObservedObject var bottle: Bottle
    @State private var path = NavigationPath()
    @State private var programLoading: Bool = false
    @State private var installStatus: String?
    @State private var showWinetricksSheet: Bool = false

    private let gridLayout = [GridItem(.adaptive(minimum: 100, maximum: .infinity))]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pinned apps")
                            .font(.headline)

                        if bottle.pinnedPrograms.isEmpty {
                            Text("Pin installed apps here for quick access.")
                                .foregroundStyle(.secondary)
                        }

                        LazyVGrid(columns: gridLayout, alignment: .center) {
                            ForEach(bottle.pinnedPrograms, id: \.id) { pinnedProgram in
                                PinView(
                                    bottle: bottle, program: pinnedProgram.program, pin: pinnedProgram.pin, path: $path
                                )
                            }
                            PinAddView(bottle: bottle)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Installed apps")
                            .font(.headline)

                        if installedPrograms.isEmpty {
                            ContentUnavailableView {
                                Label("No installed apps yet", systemImage: "app.dashed")
                            } description: {
                                Text("Install a Windows app into this bottle to get started.")
                            } actions: {
                                Button("Install app") {
                                    installApp()
                                }
                            }
                        } else {
                            ForEach(installedPrograms.prefix(6), id: \.url) { program in
                                Button {
                                    program.run()
                                } label: {
                                    Label(program.name, systemImage: "play.circle")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                            NavigationLink(value: BottleStage.programs) {
                                Label("Show all installed apps", systemImage: "list.bullet")
                            }
                        }
                    }

                    HStack {
                        Button("Install app", systemImage: "square.and.arrow.down") {
                            installApp()
                        }
                        NavigationLink(value: BottleStage.config) {
                            Label("Bottle settings", systemImage: "gearshape")
                        }
                    }
                }
                .padding()
            }
            .bottomBar {
                HStack {
                    Spacer()
                    Button("button.cDrive") {
                        bottle.openCDrive()
                    }
                    Button("button.terminal") {
                        bottle.openTerminal()
                    }
                    Button("button.winetricks") {
                        showWinetricksSheet.toggle()
                    }
                    Button("Install app") {
                        installApp()
                    }
                    .disabled(programLoading)
                    if programLoading {
                        Spacer()
                            .frame(width: 10)
                        ProgressView()
                            .controlSize(.small)
                        if let installStatus {
                            Text(installStatus)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .onAppear {
                updateStartMenu()
            }
            .disabled(!bottle.isAvailable)
            .navigationTitle(bottle.settings.name)
            .sheet(isPresented: $showWinetricksSheet) {
                WinetricksView(bottle: bottle)
            }
            .onChange(of: bottle.settings) { oldValue, newValue in
                guard oldValue != newValue else { return }
                // Trigger a reload
                BottleVM.shared.bottles = BottleVM.shared.bottles
            }
            .navigationDestination(for: BottleStage.self) { stage in
                switch stage {
                case .config:
                    ConfigView(bottle: bottle)
                case .programs:
                    ProgramsView(
                        bottle: bottle, path: $path
                    )
                case .processes:
                    RunningProcessesView(bottle: bottle)
                }
            }
            .navigationDestination(for: Program.self) { program in
                ProgramView(program: program)
            }
        }
    }

    private func updateStartMenu() {
        bottle.updateInstalledPrograms()

        let startMenuPrograms = bottle.getStartMenuPrograms()
        for startMenuProgram in startMenuPrograms {
            for program in bottle.programs where
            // For some godforsaken reason "foo/bar" != "foo/Bar" so...
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
        bottle.programs
            .filter { FileManager.default.fileExists(atPath: $0.url.path(percentEncoded: false)) }
            .sorted { $0.name < $1.name }
    }

    private func installApp() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType.exe,
                                     UTType(exportedAs: "com.microsoft.msi-installer"),
                                     UTType(exportedAs: "com.microsoft.bat")]
        panel.directoryURL = bottle.url.appending(path: "drive_c")
        panel.begin { result in
            programLoading = true
            installStatus = "Analyzing installer..."
            Task(priority: .userInitiated) {
                if result == .OK, let url = panel.urls.first {
                    do {
                        if url.pathExtension == "bat" {
                            try await Wine.runBatchFile(url: url, bottle: bottle)
                        } else {
                            try await Wine.runProgram(at: url, bottle: bottle) { progress in
                                Task { @MainActor in
                                    installStatus = progress.rawValue
                                }
                            }
                        }
                    } catch {
                        await showRunError(fileName: url.lastPathComponent,
                                           message: error.localizedDescription)
                    }
                }
                await MainActor.run {
                    programLoading = false
                    installStatus = nil
                    updateStartMenu()
                }
            }
        }
    }

    @MainActor private func showRunError(fileName: String, message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.message")
        alert.informativeText = String(localized: "alert.info") + " \(fileName): " + message
        alert.alertStyle = .critical
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.runModal()
    }
}

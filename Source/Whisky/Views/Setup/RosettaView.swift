//
//  RosettaView.swift
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

struct RosettaView: View {
    @State var installing: Bool = true
    @State var successful: Bool = true
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool

    var body: some View {
        BourbonPanelBackdrop {
            BourbonFloatingPanel(maxWidth: 560) {
                VStack(spacing: 22) {
                    Text("setup.rosetta")
                        .font(.largeTitle.bold())
                    Text("setup.rosetta.subtitle")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Group {
                        if installing {
                            ProgressView()
                                .scaleEffect(2)
                        } else if successful {
                            Image(systemName: "checkmark.circle")
                                .resizable()
                                .foregroundStyle(.green)
                                .frame(width: 80, height: 80)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "xmark.circle")
                                    .resizable()
                                    .foregroundStyle(.red)
                                    .frame(width: 80, height: 80)
                                Text("setup.rosetta.fail")
                                    .font(.subheadline)
                            }
                        }
                    }

                    HStack {
                        if !successful {
                            Button("setup.quit") {
                                exit(0)
                            }
                            .keyboardShortcut(.cancelAction)
                            Spacer()
                            Button("setup.retry") {
                                installing = true
                                successful = true

                                Task {
                                    await checkOrInstall()
                                }
                            }
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                }
            }
        }
        .navigationTitle("Rosetta")
        .onAppear {
            Task {
                await checkOrInstall()
            }
        }
    }

    func checkOrInstall() async {
        if Rosetta2.isRosettaInstalled {
            installing = false
            await proceed()
        } else {
            do {
                successful = try await Rosetta2.installRosetta()
                installing = false
                await proceed()
            } catch {
                successful = false
                installing = false
            }
        }
    }

    func proceed() async {
        WhiskyWineInstaller.recordRuntimeEvent("runtime.bootstrap.rosetta_followup.started")
        let discovery = await Task.detached(priority: .userInitiated) {
            await WhiskyWineInstaller.discoverRuntime()
        }.value
        let runtimeReady = discovery.state == .ready
        WhiskyWineInstaller.recordRuntimeEvent(
            "runtime.bootstrap.rosetta_followup.completed",
            detail: "state=\(discovery.state.rawValue) ready=\(runtimeReady)"
        )
        if !runtimeReady {
            if discovery.state == .gatekeeperBlocked {
                WhiskyWineInstaller.recordRuntimeEvent("runtime.download.skipped_existing", detail: "state=gatekeeper_blocked")
                path.append(.whiskyWineGatekeeperRecovery)
            } else if discovery.requiresDownload {
                WhiskyWineInstaller.recordRuntimeEvent("runtime.download.required", detail: "state=\(discovery.state.rawValue)")
                path.append(.whiskyWineDownload)
            }
            return
        }

        showSetup = false
    }
}

#Preview {
    RosettaView(path: .constant([]), showSetup: .constant(true))
}

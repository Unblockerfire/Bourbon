//
//  WhiskyWineInstallView.swift
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

import Foundation
import SwiftUI
import WhiskyKit

struct WhiskyWineInstallView: View {
    @State var installing: Bool = true
    @State private var errorMessage: String?
    @State private var installStatus = "Preparing BourbonWine…"
    @Binding var tarLocation: URL
    @Binding var runtimeVersion: String?
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool
    @AppStorage("hasInstalledDependencies") private var hasInstalledDependencies = false

    var body: some View {
        BourbonPanelBackdrop {
            VStack(spacing: 18) {
                Spacer(minLength: 0)

                BourbonFloatingPanel(maxWidth: 560) {
                    VStack(spacing: 18) {
                        Text("Installing BourbonWine")
                            .font(.largeTitle.bold())
                        Text("Preparing the runtime Bourbon uses to open Windows apps.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        if installing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.large)
                            Text(installStatus)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else if let errorMessage {
                            VStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(BourbonStyle.amber)
                                Text(errorMessage)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                Button("Retry") {
                                    if !path.isEmpty {
                                        path.removeLast()
                                    }
                                }
                                .buttonStyle(BourbonPrimaryButtonStyle())
                            }
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .resizable()
                                .frame(width: 76, height: 76)
                                .foregroundStyle(.green)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .navigationTitle("Installing BourbonWine")
        .onAppear {
            let archiveURL = tarLocation
            let installedRuntimeVersion = runtimeVersion
            Task {
                WhiskyWineInstaller.recordRuntimeEvent("runtime.retry.started")
                WhiskyWineInstaller.recordRuntimeEvent("runtime.archive.selected")
                var outcome = "cancelled"
                defer {
                    installing = false
                    WhiskyWineInstaller.recordRuntimeEvent(
                        "runtime.ui.finalized",
                        detail: "outcome=\(outcome)"
                    )
                }
                do {
                    installStatus = "Installing BourbonWine…"
                    try await Task.detached(priority: .userInitiated) {
                        try WhiskyWineInstaller.install(
                            from: archiveURL,
                            runtimeVersion: installedRuntimeVersion
                        )
                    }.value
                    installStatus = "Checking BourbonWine…"
                    let runtimeReady = await Task.detached(priority: .userInitiated) {
                        WhiskyWineInstaller.isWhiskyWineInstalled()
                    }.value
                    WhiskyWineInstaller.recordRuntimeEvent(
                        "runtime.readiness.completed",
                        detail: "ready=\(runtimeReady)"
                    )
                    guard runtimeReady else {
                        throw NSError(
                            domain: "BourbonWineInstall",
                            code: 1,
                            userInfo: [
                                NSLocalizedDescriptionKey:
                                    "BourbonWine was installed, but its readiness check did not pass. Try again."
                            ]
                        )
                    }
                    outcome = "success"
                    proceed(runtimeReady: runtimeReady)
                } catch is CancellationError {
                    errorMessage = "BourbonWine installation was cancelled. You can retry safely."
                } catch {
                    outcome = "failure"
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func proceed(runtimeReady: Bool) {
        hasInstalledDependencies = runtimeReady
        installing = false
        path.removeAll()
    }
}

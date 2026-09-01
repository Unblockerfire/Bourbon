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
    @State private var installTask: Task<Void, Never>?
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
                                    WhiskyWineInstaller.recordRuntimeEvent(
                                        "runtime.retry.started",
                                        detail: "source=setup_install"
                                    )
                                    install()
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
            install()
        }
        .onDisappear {
            installTask?.cancel()
        }
    }

    private func install() {
        let archiveURL = tarLocation
        let installedRuntimeVersion = runtimeVersion
        installing = true
        errorMessage = nil
        installTask = Task {
            var outcome = "failure"
            defer {
                installing = false
                installTask = nil
                WhiskyWineInstaller.recordRuntimeEvent(
                    "runtime.ui.finalized",
                    detail: "surface=setup_install outcome=\(outcome)"
                )
            }
            do {
                let worker = Task.detached(priority: .userInitiated) {
                    try WhiskyWineInstaller.install(
                        from: archiveURL,
                        runtimeVersion: installedRuntimeVersion
                    )
                }
                try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                outcome = "success"
                proceed(runtimeReady: true)
            } catch is CancellationError {
                outcome = "cancelled"
                errorMessage = "BourbonWine installation was cancelled. The existing runtime was preserved."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func proceed(runtimeReady: Bool) {
        hasInstalledDependencies = runtimeReady
        installing = false
        path.removeAll()
    }
}

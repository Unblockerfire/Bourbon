//
//  WhiskyWineGatekeeperRecoveryView.swift
//  Whisky
//

import AppKit
import SwiftUI
import WhiskyKit

struct WhiskyWineGatekeeperRecoveryView: View {
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool
    let onRuntimeReady: () -> Void
    @AppStorage("hasInstalledDependencies") private var hasInstalledDependencies = false
    @State private var retrying = false
    @State private var errorMessage: String?

    var body: some View {
        BourbonPanelBackdrop {
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                BourbonFloatingPanel(maxWidth: 560) {
                    VStack(spacing: 18) {
                        Image(systemName: "lock.trianglebadge.exclamationmark")
                            .font(.system(size: 46))
                            .foregroundStyle(BourbonStyle.amber)
                        Text("macOS blocked BourbonWine")
                            .font(.largeTitle.bold())
                        Text("BourbonWine is installed, but macOS needs your approval before Bourbon can use it.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Open Privacy & Security") { openPrivacyAndSecurity() }
                            .buttonStyle(BourbonPrimaryButtonStyle())

                        VStack(alignment: .leading, spacing: 6) {
                            Text("1. Open Privacy & Security.")
                            Text("2. Find the blocked wine message and click Open Anyway.")
                            Text("3. Approve the macOS confirmation if it appears.")
                            Text("4. Return to Bourbon and click Retry.")
                            Text("5. Quit and reopen Bourbon if macOS asks you to.")
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.callout)
                                .foregroundStyle(BourbonStyle.amber)
                                .multilineTextAlignment(.center)
                        }

                        Button(retrying ? "Checking BourbonWine…" : "Retry") { retry() }
                            .buttonStyle(BourbonSecondaryButtonStyle())
                            .disabled(retrying)

                        if WhiskyWineInstaller.hasRestorablePreviousRuntime() {
                            Button("Restore Previous BourbonWine") { restorePrevious() }
                                .buttonStyle(BourbonSecondaryButtonStyle())
                                .disabled(retrying)
                                .help("Restore the last structurally valid BourbonWine runtime.")
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .navigationTitle("BourbonWine Approval")
    }

    private func openPrivacyAndSecurity() {
        // This documented preferences URL is supported on current macOS releases.
        // Open System Settings itself when the pane URL is unavailable.
        let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Security")
        if let pane, NSWorkspace.shared.open(pane) {
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.gatekeeper.settings_opened",
                detail: "destination=privacy_security"
            )
            return
        }
        // System Settings is the safe fallback when macOS declines the legacy
        // pane URL (as can happen on newer supported macOS versions).
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        WhiskyWineInstaller.recordRuntimeEvent(
            "runtime.gatekeeper.settings_opened",
            detail: "destination=system_settings_fallback"
        )
    }

    private func retry() {
        retrying = true
        errorMessage = nil
        Task {
            var outcome = "cancelled"
            defer {
                retrying = false
                WhiskyWineInstaller.recordRuntimeEvent("runtime.ui.finalized", detail: "outcome=\(outcome)")
            }
            do {
                _ = try await WhiskyWineInstaller.retryInstalledRuntimeReadiness()
                outcome = "success"
                hasInstalledDependencies = true
                onRuntimeReady()
            } catch let error as WineRuntimePreflightError where error.isGatekeeperBlocked {
                outcome = "gatekeeper_blocked"
                WhiskyWineInstaller.recordRuntimeEvent("runtime.gatekeeper.detected")
                errorMessage = "macOS is still blocking wine. Click Open Anyway in Privacy & Security, then retry."
            } catch is CancellationError {
                errorMessage = "BourbonWine readiness check was cancelled. Retry when you are ready."
            } catch {
                outcome = "failure"
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restorePrevious() {
        retrying = true
        errorMessage = nil
        Task {
            var outcome = "cancelled"
            defer {
                retrying = false
                WhiskyWineInstaller.recordRuntimeEvent("runtime.ui.finalized", detail: "outcome=\(outcome)")
            }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try WhiskyWineInstaller.restorePreviousRuntime()
                }.value
                _ = try await WhiskyWineInstaller.retryInstalledRuntimeReadiness()
                outcome = "restored_previous"
                hasInstalledDependencies = true
                onRuntimeReady()
            } catch {
                outcome = "restore_failed"
                errorMessage = error.localizedDescription
            }
        }
    }
}

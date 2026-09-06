//  SetupView.swift
//
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
@preconcurrency import Sparkle
import WhiskyKit

enum SetupStage {
    case rosetta
    case whiskyWineDownload
    case whiskyWineInstall
    case whiskyWineGatekeeperRecovery
}

struct SetupView: View {
    @State private var path: [SetupStage] = []
    @State var tarLocation: URL = URL(fileURLWithPath: "")
    @State var runtimeVersion: String?
    @State var runtimeSHA256: String?
    @State var manualRuntimeArchive = false
    @Binding var showSetup: Bool
    @Binding var showBottleCreation: Bool
    let updater: SPUUpdater
    var firstTime: Bool = true
    var runtimeRepairState: RuntimeDiscovery.State?
    @State private var showIntro = true
    @State private var resolvedRuntimeState: RuntimeDiscovery.State?
    @AppStorage("hasSeenIntroVideo") private var hasSeenIntroVideo = false
    @AppStorage("hasCompletedFirstRunOnboarding") private var hasCompletedFirstRunOnboarding = false

    var body: some View {
        ZStack {
            if showIntro {
                BourbonIntroVideoView(
                    buttonTitle: hasCompletedFirstRunOnboarding ? "Welcome Back!" : "Get Started",
                    startReturningUserUpdateCheck: startReturningUserUpdateCheck
                ) {
                    hasSeenIntroVideo = true
                    showIntro = false
                    BourbonPendingUpdateManager.shared.finishIntroUpdateDeferral()
                }
                .transition(.opacity)
            } else {
                NavigationStack(path: $path) {
                    WelcomeView(
                        path: $path,
                        showSetup: $showSetup,
                        showBottleCreation: $showBottleCreation,
                        firstTime: firstTime,
                        runtimeRepairState: $resolvedRuntimeState
                    )
                    .navigationBarBackButtonHidden(true)
                    .navigationDestination(for: SetupStage.self) { stage in
                        switch stage {
                        case .rosetta:
                            RosettaView(path: $path, showSetup: $showSetup)
                        case .whiskyWineDownload:
                            WhiskyWineDownloadView(
                                tarLocation: $tarLocation,
                                runtimeVersion: $runtimeVersion,
                                runtimeSHA256: $runtimeSHA256,
                                manualRuntimeArchive: $manualRuntimeArchive,
                                path: $path,
                                onRuntimeReady: runtimeBecameReady
                            )
                        case .whiskyWineInstall:
                            WhiskyWineInstallView(
                                tarLocation: $tarLocation,
                                runtimeVersion: $runtimeVersion,
                                runtimeSHA256: $runtimeSHA256,
                                manualRuntimeArchive: $manualRuntimeArchive,
                                path: $path,
                                showSetup: $showSetup,
                                onRuntimeReady: runtimeBecameReady
                            )
                        case .whiskyWineGatekeeperRecovery:
                            WhiskyWineGatekeeperRecoveryView(
                                path: $path,
                                showSetup: $showSetup,
                                onRuntimeReady: runtimeBecameReady
                            )
                        }
                    }
                }
            }
        }
        .onAppear {
            if resolvedRuntimeState == nil { resolvedRuntimeState = runtimeRepairState }
            if hasSeenIntroVideo {
                showIntro = false
            }
            routeReturningUserToRuntimeRecovery()
        }
    }

    private func runtimeBecameReady() {
        resolvedRuntimeState = .ready
        path.removeAll()
        if hasCompletedFirstRunOnboarding { showSetup = false }
    }

    private func startReturningUserUpdateCheck() {
        guard hasCompletedFirstRunOnboarding,
              updater.canCheckForUpdates,
              BourbonPendingUpdateManager.shared.beginIntroUpdateCheck() else {
            return
        }

        updater.checkForUpdatesInBackground()
    }

    private func routeReturningUserToRuntimeRecovery() {
        guard !firstTime, path.isEmpty else { return }
        switch RuntimeStartupRouting.route(
            onboardingCompleted: hasCompletedFirstRunOnboarding,
            runtimeState: runtimeRepairState
        ) {
        case .gatekeeperRecovery:
            path = [.whiskyWineGatekeeperRecovery]
        case .runtimeRepair, .onboarding, .home:
            break
        }
    }
}

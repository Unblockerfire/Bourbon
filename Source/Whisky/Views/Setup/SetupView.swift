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

enum SetupStage {
    case rosetta
    case whiskyWineDownload
    case whiskyWineInstall
}

struct SetupView: View {
    @State private var path: [SetupStage] = []
    @State var tarLocation: URL = URL(fileURLWithPath: "")
    @Binding var showSetup: Bool
    @Binding var showBottleCreation: Bool
    let updater: SPUUpdater
    var firstTime: Bool = true
    @State private var showIntro = true
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
                        firstTime: firstTime
                    )
                    .navigationBarBackButtonHidden(true)
                    .navigationDestination(for: SetupStage.self) { stage in
                        switch stage {
                        case .rosetta:
                            RosettaView(path: $path, showSetup: $showSetup)
                        case .whiskyWineDownload:
                            WhiskyWineDownloadView(tarLocation: $tarLocation, path: $path)
                        case .whiskyWineInstall:
                            WhiskyWineInstallView(tarLocation: $tarLocation, path: $path, showSetup: $showSetup)
                        }
                    }
                }
            }
        }
    }

    private func startReturningUserUpdateCheck() {
        guard hasCompletedFirstRunOnboarding,
              updater.canCheckForUpdates,
              BourbonPendingUpdateManager.shared.beginIntroUpdateCheck() else {
            return
        }

        updater.checkForUpdatesInBackground()
    }
}

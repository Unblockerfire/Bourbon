//
//  BottleVM.swift
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
import SemanticVersion
import WhiskyKit

// swiftlint:disable:next todo
// TODO: Don't use unchecked!
@MainActor
final class BottleVM: ObservableObject {

    var bottlesList = BottleData()
    @Published var bottles: [Bottle] = []

    @MainActor
    func loadBottles() {
        bottles = bottlesList.loadBottles()
    }

    func countActive() -> Int {
        return bottles.filter { $0.isAvailable == true }.count
    }

    @MainActor
    func createNewBottle(bottleName: String, winVersion: WinVersion, bottleURL: URL) async throws -> URL {
        let newBottleDir = bottleURL.appending(path: UUID().uuidString)
        var createdDirectory = false

        do {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: newBottleDir, withIntermediateDirectories: true)
            createdDirectory = true
            try Task.checkCancellation()

            let bottle = Bottle(bottleUrl: newBottleDir, inFlight: true)
            bottle.settings.windowsVersion = winVersion
            bottle.settings.name = bottleName
            bottles.append(bottle)

            try await Wine.changeWinVersion(bottle: bottle, win: winVersion)
            try Task.checkCancellation()
            let wineVer = try await Wine.wineVersion()
            try Task.checkCancellation()
            guard let semanticWineVersion = SemanticVersion(wineVer) else {
                throw BottleCreationError.invalidWineVersion
            }
            bottle.settings.wineVersion = semanticWineVersion
            bottle.inFlight = false
            bottlesList.paths.append(newBottleDir)
            loadBottles()
            return newBottleDir
        } catch {
            bottles.removeAll { $0.url == newBottleDir }
            bottlesList.paths.removeAll { $0 == newBottleDir }
            if createdDirectory {
                try? FileManager.default.removeItem(at: newBottleDir)
            }
            throw error
        }
    }
}

enum BottleCreationError: Error {
    case invalidWineVersion
}

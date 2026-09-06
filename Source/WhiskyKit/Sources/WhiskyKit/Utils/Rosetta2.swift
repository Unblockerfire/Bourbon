//
//  Rosetta2.swift
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
import os.log

public class Rosetta2 {
    private static let rosetta2RuntimeBin = "/Library/Apple/usr/libexec/oah/libRosettaRuntime"

    public static let isRosettaInstalled: Bool = {
        return FileManager.default.fileExists(atPath: rosetta2RuntimeBin)
    }()

    /// BourbonWine is currently x86_64. It needs Rosetta only on Apple Silicon;
    /// it runs natively on Intel Macs.
    public static var isRequiredForBourbonWine: Bool {
        HostArchitecture.current.requiresRosettaForX86Runtime
    }

    public static func bourbonWineDependenciesAreReady(
        rosettaInstalled: Bool,
        runtimeReady: Bool,
        hostArchitecture: HostArchitecture = .current
    ) -> Bool {
        runtimeReady && (!hostArchitecture.requiresRosettaForX86Runtime || rosettaInstalled)
    }

    public static func installRosetta() async throws -> Bool {
        let process = Process()
        let fileHandle = try Wine.makeFileHandle()

        process.launchPath = "/usr/sbin/softwareupdate"
        process.arguments = ["--install-rosetta", "--agree-to-license"]
        process.standardOutput = fileHandle
        process.standardError = fileHandle
        fileHandle.writeApplicaitonInfo()
        fileHandle.writeInfo(for: process)

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { (process: Process) in
                do {
                    try fileHandle.close()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    Logger.wineKit.error("Error while closing file handle: \(error)")
                    continuation.resume(throwing: error)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

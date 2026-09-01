//
//  Tar.swift
//  WhiskyKit
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
#if canImport(Darwin)
import Darwin
#endif

public class Tar {
    static let tarBinary: URL = URL(fileURLWithPath: "/usr/bin/tar")

    public static func tar(folder: URL, toURL: URL) throws {
        _ = try run(arguments: ["-zcf", toURL.path, folder.path], timeout: 300)
    }

    public static func untar(tarBall: URL, toURL: URL) throws {
        _ = try run(arguments: ["-xzf", tarBall.path, "-C", toURL.path], timeout: 300)
    }

    public static func list(tarBall: URL) throws -> [String] {
        let output = try run(arguments: ["-tzf", tarBall.path], timeout: 60)
        return output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    private static func run(arguments: [String], timeout: TimeInterval) throws -> String {
        let process = Process()
        process.executableURL = tarBinary
        process.arguments = arguments

        let fileManager = FileManager.default
        let captureURL = fileManager.temporaryDirectory
            .appending(path: "BourbonTar-\(UUID().uuidString).log")
        guard fileManager.createFile(atPath: captureURL.path, contents: nil) else {
            throw "Bourbon could not create a temporary tar diagnostic capture."
        }
        defer { try? fileManager.removeItem(at: captureURL) }

        let writer = try FileHandle(forWritingTo: captureURL)
        process.standardOutput = writer
        process.standardError = writer
        do {
            try process.run()
        } catch {
            try? writer.close()
            throw error
        }
        try? writer.close()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            if withUnsafeCurrentTask(body: { $0?.isCancelled ?? false }) {
                stop(process)
                throw CancellationError()
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            stop(process)
            throw "tar timed out after \(Int(timeout)) seconds."
        }

        let data = (try? Data(contentsOf: captureURL)) ?? Data()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw output.isEmpty ? "tar failed with exit status \(process.terminationStatus)." : output
        }
        return output
    }

    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(1)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        #if canImport(Darwin)
        if process.isRunning {
            _ = Darwin.kill(process.processIdentifier, SIGKILL)
            let killDeadline = Date().addingTimeInterval(1)
            while process.isRunning && Date() < killDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        #endif
    }
}

extension String: @retroactive Error {}

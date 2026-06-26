//
//  SevenZipExtractor.swift
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
import os.log

struct SevenZipExtractor: Sendable {
    enum ExtractionError: LocalizedError {
        case toolUnavailable
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .toolUnavailable:
                return "No compatible archive extractor is available."
            case .failed(let message):
                return message
            }
        }
    }

    let executableURL: URL

    static func available() -> SevenZipExtractor? {
        let fileManager = FileManager.default
        let candidates = [
            Bundle.main.url(forResource: "7zz", withExtension: nil),
            Bundle.main.url(forResource: "7z", withExtension: nil),
            Bundle.main.url(forResource: "7za", withExtension: nil),
            URL(fileURLWithPath: "/opt/homebrew/bin/7z"),
            URL(fileURLWithPath: "/opt/homebrew/bin/7za"),
            URL(fileURLWithPath: "/usr/local/bin/7z"),
            URL(fileURLWithPath: "/usr/local/bin/7za")
        ].compactMap { $0 }

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            return SevenZipExtractor(executableURL: candidate)
        }

        let pathItems = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        for directory in pathItems {
            for name in ["7zz", "7z", "7za"] {
                let candidate = URL(fileURLWithPath: directory).appending(path: name)
                if fileManager.isExecutableFile(atPath: candidate.path) {
                    return SevenZipExtractor(executableURL: candidate)
                }
            }
        }

        return nil
    }

    func list(archive: URL) throws -> String {
        try run(["l", "-ba", archive.path(percentEncoded: false)])
    }

    func extract(archive: URL, to destination: URL, include: String? = nil) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var arguments = [
            "x",
            "-y",
            "-bd",
            "-bb0",
            archive.path(percentEncoded: false),
            "-o\(destination.path(percentEncoded: false))"
        ]
        if let include {
            arguments.append(include)
        }
        _ = try run(arguments)
    }

    private func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            Logger.wineKit.warning("Archive extraction failed: \(output, privacy: .public)")
            throw ExtractionError.failed(output)
        }
        return output
    }
}

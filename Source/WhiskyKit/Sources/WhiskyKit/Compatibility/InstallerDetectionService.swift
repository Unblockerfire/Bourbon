//
//  InstallerDetectionService.swift
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

public struct InstallerDetectionService: Sendable {
    private let scanner = FilePatternScanner()

    public init() {}

    public func analyze(url: URL) throws -> InstallerAnalysis {
        let pathExtension = url.pathExtension.lowercased()
        let matches = try scanner.scan(url: url, patterns: Self.patterns)
        let peMetadata = peMetadata(url: url, pathExtension: pathExtension)

        return InstallerAnalysis(
            url: url,
            technologies: technologies(url: url, pathExtension: pathExtension, matches: matches),
            architecture: peMetadata.architecture,
            peType: peMetadata.peType,
            payloadHints: payloadHints(from: matches),
            cacheKey: cacheKey(for: url)
        )
    }

    private static let patterns: [FilePatternScanner.Pattern<InstallerPattern>] = [
        .init(id: .nsis, needles: ["Nullsoft", "NSIS", "$PLUGINSDIR"]),
        .init(id: .innoSetup, needles: ["Inno Setup", "SetupLdr", "JR.Inno"]),
        .init(id: .installShield, needles: ["InstallShield", "InstallScript", "ISSetup"]),
        .init(id: .squirrel, needles: ["Squirrel", "SquirrelAwareVersion", "Update.exe", "RELEASES"]),
        .init(id: .electron, needles: ["Electron", "app.asar", "electron.exe", "Chrome/"]),
        .init(id: .chromium, needles: ["Chromium", "Chrome/"]),
        .init(id: .cef, needles: ["libcef", "CEF", "Chromium Embedded Framework", "cefclient"]),
        .init(id: .steamWebView, needles: ["steamwebhelper", "steamui", "steamclient", "Valve Corporation"]),
        .init(id: .app64Archive, needles: ["app-64.7z"]),
        .init(id: .app32Archive, needles: ["app-32.7z"]),
        .init(id: .nupkg, needles: [".nupkg"])
    ]

    private func hasMSIHeader(url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer {
            try? handle.close()
        }
        guard let data = try? handle.read(upToCount: 8), data.count == 8 else {
            return false
        }
        return data == Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
    }

    private func peMetadata(url: URL, pathExtension: String) -> (architecture: Architecture, peType: String) {
        guard pathExtension == "exe", let peFile = try? PEFile(url: url) else {
            return (.unknown, "unknown")
        }
        return (peFile.architecture, peFile.optionalHeader?.magic.description ?? "unknown")
    }

    private func technologies(
        url: URL,
        pathExtension: String,
        matches: Set<InstallerPattern>
    ) -> Set<InstallerTechnology> {
        var result: Set<InstallerTechnology> = []
        if pathExtension == "msi" || hasMSIHeader(url: url) {
            result.insert(.msi)
        }

        let mapping: [(InstallerPattern, InstallerTechnology)] = [
            (.nsis, .nsis),
            (.innoSetup, .innoSetup),
            (.installShield, .installShield),
            (.squirrel, .squirrel),
            (.electron, .electron),
            (.chromium, .chromium),
            (.cef, .cef),
            (.steamWebView, .steamWebView)
        ]
        for (pattern, technology) in mapping where matches.contains(pattern) {
            result.insert(technology)
        }

        let executableName = url.deletingPathExtension().lastPathComponent.lowercased()
        if executableName == "steam" || executableName.contains("steamwebhelper") {
            result.insert(.steamWebView)
        }

        let installerTechnologies: Set<InstallerTechnology> = [.msi, .nsis, .innoSetup, .installShield, .squirrel]
        if pathExtension == "exe", result.isDisjoint(with: installerTechnologies) {
            result.insert(.portableExecutable)
        }
        if result.isEmpty {
            result.insert(.unknown)
        }
        return result
    }

    private func payloadHints(from matches: Set<InstallerPattern>) -> Set<String> {
        var result: Set<String> = []
        if matches.contains(.app64Archive) {
            result.insert("app-64.7z")
        }
        if matches.contains(.app32Archive) {
            result.insert("app-32.7z")
        }
        if matches.contains(.nupkg) {
            result.insert(".nupkg")
        }
        return result
    }

    private func cacheKey(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize ?? 0
        let modified = Int(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
        let name = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
        return "\(name)-\(size)-\(modified)"
    }
}

private enum InstallerPattern: Sendable {
    case nsis
    case innoSetup
    case installShield
    case squirrel
    case electron
    case chromium
    case cef
    case steamWebView
    case app64Archive
    case app32Archive
    case nupkg
}

private struct FilePatternScanner: Sendable {
    struct Pattern<ID: Hashable & Sendable>: Sendable {
        let id: ID
        let needles: [String]
    }

    func scan<ID: Hashable & Sendable>(url: URL, patterns: [Pattern<ID>]) throws -> Set<ID> {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        let compiled = patterns.map { pattern in
            (pattern.id, pattern.needles.map { Data($0.utf8).asciiLowercased() })
        }
        let overlap = compiled.flatMap(\.1).map(\.count).max() ?? 0
        var previous = Data()
        var matches = Set<ID>()

        while true {
            guard let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty else {
                break
            }

            var searchable = previous
            searchable.append(chunk)
            searchable = searchable.asciiLowercased()

            for (id, needles) in compiled where !matches.contains(id) {
                if needles.contains(where: { searchable.range(of: $0) != nil }) {
                    matches.insert(id)
                }
            }

            if searchable.count > overlap {
                previous = searchable.suffix(overlap)
            } else {
                previous = searchable
            }
        }

        return matches
    }
}

private extension Data {
    func asciiLowercased() -> Data {
        Data(map { byte in
            if byte >= 65 && byte <= 90 {
                return byte + 32
            }
            return byte
        })
    }
}

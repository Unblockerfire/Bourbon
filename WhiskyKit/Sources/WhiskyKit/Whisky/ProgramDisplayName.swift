//
//  ProgramDisplayName.swift
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

public enum ProgramDisplayName {
    public static func friendlyName(for url: URL, preferredName: String? = nil) -> String {
        let rawName = versionMetadataName(for: url)
            ?? preferredName.flatMap(nonEmpty)
            ?? url.deletingPathExtension().lastPathComponent
        return clean(rawName)
    }

    private static func versionMetadataName(for url: URL) -> String? {
        (try? PEFile(url: url))?.versionDisplayName
    }

    private static func clean(_ rawName: String) -> String {
        let extensionless = URL(fileURLWithPath: rawName).deletingPathExtension().lastPathComponent
        let spaced = extensionless
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !spaced.isEmpty else { return rawName }
        if spaced == spaced.lowercased() {
            return spaced
                .split(separator: " ")
                .map { word in word.prefix(1).uppercased() + String(word.dropFirst()) }
                .joined(separator: " ")
        }
        return spaced
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

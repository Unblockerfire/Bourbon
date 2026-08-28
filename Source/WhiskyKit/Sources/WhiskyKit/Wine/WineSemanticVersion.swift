//
//  WineSemanticVersion.swift
//  WhiskyKit
//
//  This file is part of Whisky.
//

import Foundation
import SemanticVersion

public enum WineVersionError: LocalizedError, Sendable, Equatable {
    case invalidOutput

    public var errorDescription: String? {
        "Wine did not return a recognizable version."
    }
}

public enum WineSemanticVersion {
    /// Returns the version token emitted by `wine --version`.
    ///
    /// A normal Wine process prints values such as
    /// `wine-11.11-199-ge3bb4552d76\n`. Keeping this normalization here makes
    /// the production command-output contract independently testable.
    public static func versionToken(from rawOutput: String) -> String? {
        var value = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("wine-") {
            value.removeFirst("wine-".count)
        }

        if let suffixStart = value.firstIndex(where: { $0.isWhitespace }) {
            value = String(value[..<suffixStart])
        }

        return value.isEmpty ? nil : value
    }

    public static func requireVersionToken(from rawOutput: String) throws -> String {
        guard let version = versionToken(from: rawOutput) else {
            throw WineVersionError.invalidOutput
        }
        return version
    }

    /// Parses Wine's version output without accepting unrelated malformed values.
    ///
    /// Wine development builds may omit the patch component, for example
    /// `11.11-199-ge3bb4552d76`. SemanticVersion requires three numeric
    /// components, so those values are normalized to `11.11.0-199-ge3bb4552d76`.
    public static func parse(_ rawValue: String) -> SemanticVersion? {
        guard let value = versionToken(from: rawValue) else { return nil }

        if let version = SemanticVersion(value) {
            return version
        }

        let suffixStart = value.firstIndex { character in
            character == "-" || character == "+"
        }
        let core = suffixStart.map { String(value[..<$0]) } ?? value
        let suffix = suffixStart.map { String(value[$0...]) } ?? ""
        let components = core.split(separator: ".", omittingEmptySubsequences: false)

        guard components.count == 2,
              components.allSatisfy({ component in
                  !component.isEmpty && component.allSatisfy { $0.isNumber }
              }),
              suffix.isEmpty || suffix.count > 1 else {
            return nil
        }

        return SemanticVersion("\(components[0]).\(components[1]).0\(suffix)")
    }
}

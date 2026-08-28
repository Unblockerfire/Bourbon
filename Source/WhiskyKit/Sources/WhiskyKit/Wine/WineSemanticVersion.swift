//
//  WineSemanticVersion.swift
//  WhiskyKit
//
//  This file is part of Whisky.
//

import Foundation
import SemanticVersion

public enum WineSemanticVersion {
    /// Parses Wine's version output without accepting unrelated malformed values.
    ///
    /// Wine development builds may omit the patch component, for example
    /// `11.11-199-ge3bb4552d76`. SemanticVersion requires three numeric
    /// components, so those values are normalized to `11.11.0-199-ge3bb4552d76`.
    public static func parse(_ rawValue: String) -> SemanticVersion? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

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

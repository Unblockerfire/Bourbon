//
//  ProgramDiscovery.swift
//  WhiskyKit
//

import Foundation

/// Classifies Windows executables found while scanning a Bottle. Discovery
/// deliberately excludes infrastructure tools so that a user-facing launcher
/// is not displaced by diagnostics, redistributables, or helper binaries.
public enum ProgramDiscovery {
    private static let excludedNames: Set<String> = [
        "wine", "wine64", "winecfg", "winefile", "uninstaller", "regedit",
        "cmd", "notepad", "wordpad", "iexplore", "oleview", "winemine",
        "fossilize replay", "fossilize replay64", "fossilizereplay",
        "fossilizereplay64", "gldriverquery", "gl driver query", "vulkaninfo",
        "dxdiag", "dxsetup", "crashhandler", "crashreporter", "crashpad_handler",
        "steamwebhelper", "steamservice", "unins000", "uninstall"
    ]

    private static let excludedTokens: Set<String> = [
        "crash", "crashpad", "diagnostic", "diagnostics", "helper", "uninstall",
        "unins", "redistributable", "redist", "vcredist", "fossilize",
        "gldriverquery", "glquery", "vulkaninfo", "dxdiag", "dxsetup"
    ]

    public static func isUserFacingExecutable(at url: URL) -> Bool {
        let basename = url.deletingPathExtension().lastPathComponent
        let normalizedName = normalize(basename)
        guard !excludedNames.contains(normalizedName) else { return false }

        let tokens = Set(normalizedName.split(separator: " ").map(String.init))
        return excludedTokens.isDisjoint(with: tokens)
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

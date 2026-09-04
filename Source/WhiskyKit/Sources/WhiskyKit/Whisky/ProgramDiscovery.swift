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

    /// A stable identity for an executable within a Wine prefix. Wine paths are
    /// case-insensitive in normal use, and aliases/symlinks must not create a
    /// second entry for the same executable.
    public static func canonicalExecutablePath(for url: URL) -> String {
        url
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path(percentEncoded: false)
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }

    /// Returns eligible applications introduced by an installer, with aliases
    /// and duplicate scan results collapsed to one canonical executable path.
    public static func newlyInstalledExecutables(before: [URL], after: [URL]) -> [URL] {
        let existing = Set(before.map(canonicalExecutablePath(for:)))
        var seen = Set<String>()

        return after.filter { url in
            let identifier = canonicalExecutablePath(for: url)
            return !existing.contains(identifier)
                && seen.insert(identifier).inserted
                && isUserFacingExecutable(at: url)
        }
    }

    /// Chooses a deterministic primary launcher from applications newly found
    /// after an install. A binary named for its containing application folder
    /// is strongly preferred (for example Notepad++/notepad++.exe).
    public static func preferredExecutable(from urls: [URL]) -> URL? {
        urls
            .filter(isUserFacingExecutable(at:))
            .sorted { lhs, rhs in
                let leftScore = primaryLauncherScore(lhs)
                let rightScore = primaryLauncherScore(rhs)
                if leftScore != rightScore { return leftScore > rightScore }
                return canonicalExecutablePath(for: lhs) < canonicalExecutablePath(for: rhs)
            }
            .first
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            // Keep '+' meaningful: Notepad++ is an application name, not the
            // Wine built-in `notepad` executable.
            .replacingOccurrences(of: "[^a-z0-9+]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func primaryLauncherScore(_ url: URL) -> Int {
        let executableName = normalize(url.deletingPathExtension().lastPathComponent)
        let folderName = normalize(url.deletingLastPathComponent().lastPathComponent)
        var score = executableName == folderName ? 1_000 : 0

        // An application binary directly below its product folder is normally
        // the user-facing launcher; deeper paths are usually support binaries.
        score -= url.pathComponents.count
        return score
    }
}

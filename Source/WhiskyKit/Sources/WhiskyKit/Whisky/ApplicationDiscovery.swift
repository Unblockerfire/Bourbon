import Foundation

public struct ApplicationDiscoveryReport: Equatable, Sendable {
    public let rawCandidateCount: Int
    public let acceptedApplicationCount: Int
    public let rejectedHelperCount: Int

    public init(rawCandidateCount: Int, acceptedApplicationCount: Int, rejectedHelperCount: Int) {
        self.rawCandidateCount = rawCandidateCount
        self.acceptedApplicationCount = acceptedApplicationCount
        self.rejectedHelperCount = rejectedHelperCount
    }

    /// This intentionally contains no paths: it is safe to include in diagnostics.
    public var diagnosticSummary: String {
        "raw_candidates=\(rawCandidateCount) accepted_apps=\(acceptedApplicationCount) rejected_helpers=\(rejectedHelperCount)"
    }
}

public enum ApplicationDiscovery {
    /// Windows paths are case-insensitive even when the bottle is stored on a
    /// case-sensitive macOS volume.
    public static func canonicalIdentifier(for url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased()
    }

    public static func isEligibleExecutable(_ url: URL) -> Bool {
        guard url.pathExtension.caseInsensitiveCompare("exe") == .orderedSame else { return false }
        let name = url.lastPathComponent.lowercased()
        let path = canonicalIdentifier(for: url)

        let exactHelpers: Set<String> = [
            "gup.exe", "gldriverquery.exe", "gldriverquery64.exe",
            "hardwareupdater.exe", "fossilize replay.exe", "fossilize replay64.exe",
            "uninstall.exe", "uninstaller.exe", "unins000.exe", "crashpad_handler.exe"
        ]
        if exactHelpers.contains(name) { return false }

        let helperTokens = [
            "uninstall", "updater", "updatehelper", "update_helper", "crashreport",
            "crashpad", "service", "helper", "redistributable", "fossilize",
            "gldriverquery", "hardwareupdater"
        ]
        if helperTokens.contains(where: { name.contains($0) || path.contains("/\($0)/") }) {
            return false
        }
        return true
    }

    public static func deduplicatedEligibleURLs(_ urls: [URL]) -> (urls: [URL], report: ApplicationDiscoveryReport) {
        var seen = Set<String>()
        var accepted: [URL] = []
        var rejectedHelpers = 0
        for url in urls {
            guard isEligibleExecutable(url) else {
                rejectedHelpers += 1
                continue
            }
            if seen.insert(canonicalIdentifier(for: url)).inserted {
                accepted.append(url)
            }
        }
        return (
            accepted,
            ApplicationDiscoveryReport(
                rawCandidateCount: urls.count,
                acceptedApplicationCount: accepted.count,
                rejectedHelperCount: rejectedHelpers
            )
        )
    }
}

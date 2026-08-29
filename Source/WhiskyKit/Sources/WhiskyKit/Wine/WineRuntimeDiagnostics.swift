//
//  WineRuntimeDiagnostics.swift
//  WhiskyKit
//

import Foundation

public struct WineRuntimePreflightResult: Sendable {
    public let version: String
}

public enum WineRuntimePreflightError: LocalizedError, Sendable {
    case executableMissing(path: String)
    case cannotExecute(path: String, details: String)
    case rosettaUnavailable(details: String)
    case runtimeLibraryFailure(details: String)
    case processNonzero(status: Int32, details: String)
    case invalidWineOutput(details: String)

    public var errorDescription: String? {
        switch self {
        case .executableMissing(let path):
            return "The BourbonWine executable is missing at \(path)."
        case .cannotExecute(let path, let details):
            return "Bourbon cannot execute Wine at \(path). \(details)"
        case .rosettaUnavailable(let details):
            return "Wine could not start through Rosetta. \(details)"
        case .runtimeLibraryFailure(let details):
            return "Wine could not load its runtime libraries. \(details)"
        case .processNonzero(let status, let details):
            return "Wine's runtime preflight exited with status \(status). \(details)"
        case .invalidWineOutput(let details):
            return "Wine started, but returned an invalid version response. \(details)"
        }
    }
}

enum WineDiagnosticSanitizer {
    static let excerptLimit = 4_000

    static func excerpt(from value: String, limit: Int = excerptLimit) -> String {
        let safe = redact(value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safe.isEmpty else { return "<no output>" }
        guard safe.count > limit else { return safe }
        return "[truncated to final \(limit) characters]\n" + String(safe.suffix(limit))
    }

    static func redact(_ value: String) -> String {
        var result = value.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        result = replacing(
            pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            in: result,
            with: "[redacted-email]",
            options: [.caseInsensitive]
        )
        let sensitiveValuePattern = #"(?i)\b(token|api[_-]?key|secret|password|license(?:token)?|"#
            + #"privateLicenseToken)\b\s*[=:]\s*[^\s]+"#
        result = replacing(
            pattern: sensitiveValuePattern,
            in: result,
            with: "$1=[redacted]"
        )
        result = replacing(
            pattern: #"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{8,}"#,
            in: result,
            with: "Bearer [redacted]"
        )
        result = replacing(
            pattern: #"BRBN-[A-Za-z0-9-]{12,}"#,
            in: result,
            with: "[redacted-license-token]"
        )
        return result
    }

    static func redactEnvironment(_ environment: [String: String]) -> String {
        guard !environment.isEmpty else { return "<none>" }
        return environment.keys.sorted().map { key in
            let value = environment[key] ?? ""
            if isSensitiveEnvironmentKey(key) {
                return "\(key)=[redacted]"
            }
            return "\(key)=\(redact(value))"
        }.joined(separator: "\n")
    }

    static func filteredRuntimeEnvironment(_ environment: [String: String]) -> [String: String] {
        let prefixes = ["WINE", "DYLD", "WHISKY_", "ROSETTA", "GST_DEBUG"]
        return environment.filter { key, _ in
            key == "PATH" || prefixes.contains(where: { key.hasPrefix($0) })
        }
    }

    static func isValidVersionOutput(_ output: String) -> Bool {
        output.range(
            of: #"\bwine(?:64)?-[^\r\n]*\d"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    static func classifiedFailure(
        details: String,
        executablePath: String,
        status: Int32? = nil
    ) -> WineRuntimePreflightError {
        let excerpt = excerpt(from: details)
        let lowercased = details.lowercased()

        if lowercased.contains("bad cpu type")
            || lowercased.contains("rosetta")
            || lowercased.contains("code signature supplement") {
            return .rosettaUnavailable(details: excerpt)
        }

        if lowercased.contains("library not loaded")
            || lowercased.contains("dyld")
            || lowercased.contains("dylib")
            || lowercased.contains("symbol not found")
            || lowercased.contains("image not found") {
            return .runtimeLibraryFailure(details: excerpt)
        }

        if let status {
            return .processNonzero(status: status, details: excerpt)
        }
        return .cannotExecute(path: executablePath, details: excerpt)
    }

    private static func replacing(
        pattern: String,
        in value: String,
        with template: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(in: value, range: range, withTemplate: template)
    }

    private static func isSensitiveEnvironmentKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return ["token", "key", "secret", "password", "credential", "license"]
            .contains { normalized.contains($0) }
    }
}

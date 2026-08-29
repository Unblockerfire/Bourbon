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
    case rosettaUnavailable(path: String, details: String)
    case runtimeLibraryFailure(path: String, details: String)
    case processNonzero(path: String, status: Int32, details: String)
    case invalidWineOutput(path: String, details: String)

    public var diagnosticCode: String {
        switch self {
        case .executableMissing: return "executable_missing"
        case .cannotExecute: return "cannot_execute"
        case .rosettaUnavailable: return "rosetta_unavailable"
        case .runtimeLibraryFailure: return "runtime_library_failure"
        case .processNonzero: return "process_nonzero"
        case .invalidWineOutput: return "invalid_wine_output"
        }
    }

    public var unifiedLogDescription: String {
        var fields = [
            "wine_runtime_preflight_\(diagnosticCode)",
            "executable=\(safeExecutablePath)",
            "arguments=--version"
        ]
        if let exitStatus { fields.append("exit_status=\(exitStatus)") }
        fields.append("details=\(WineDiagnosticSanitizer.singleLine(safeDetails))")
        return fields.joined(separator: " ")
    }

    public var userFacingDiagnosticMessage: String {
        var message = "Wine runtime preflight failed (\(diagnosticCode)).\n"
        message += "Executable: \(safeExecutablePath)\n"
        message += "Arguments: --version\n"
        if let exitStatus { message += "Exit status: \(exitStatus)\n" }
        message += "Details: \(safeDetails)"
        return message
    }

    public var errorDescription: String? {
        switch self {
        case .executableMissing:
            return "The BourbonWine executable is missing at \(safeExecutablePath)."
        case .cannotExecute(_, let details):
            return "Bourbon cannot execute Wine at \(safeExecutablePath). " +
                WineDiagnosticSanitizer.excerpt(from: details)
        case .rosettaUnavailable(_, let details):
            return "Wine could not start through Rosetta. \(details)"
        case .runtimeLibraryFailure(_, let details):
            return "Wine could not load its runtime libraries. \(details)"
        case .processNonzero(_, let status, let details):
            return "Wine's runtime preflight exited with status \(status). \(details)"
        case .invalidWineOutput(_, let details):
            return "Wine started, but returned an invalid version response. \(details)"
        }
    }

    private var executablePath: String {
        switch self {
        case .executableMissing(let path), .cannotExecute(let path, _),
             .rosettaUnavailable(let path, _), .runtimeLibraryFailure(let path, _),
             .processNonzero(let path, _, _), .invalidWineOutput(let path, _):
            return path
        }
    }

    private var safeExecutablePath: String {
        WineDiagnosticSanitizer.displayPath(executablePath)
    }

    private var safeDetails: String {
        switch self {
        case .executableMissing:
            return "The selected executable does not exist."
        case .cannotExecute(_, let details), .rosettaUnavailable(_, let details),
             .runtimeLibraryFailure(_, let details), .processNonzero(_, _, let details),
             .invalidWineOutput(_, let details):
            return WineDiagnosticSanitizer.excerpt(from: details)
        }
    }

    private var exitStatus: Int32? {
        guard case .processNonzero(_, let status, _) = self else { return nil }
        return status
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
        result = replacing(pattern: #"(?i)(?:/Users|/home)/[^/\s]+"#, in: result, with: "~")
        result = replacing(pattern: #"(?i)[A-Z]:\\Users\\[^\\\s]+"#, in: result, with: "~")
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

    static func displayPath(_ value: String) -> String {
        let safePath = redact(value)
        if let range = safePath.range(of: "Libraries/Wine/bin/", options: [.caseInsensitive]) {
            return String(safePath[range.lowerBound...])
        }
        if safePath.hasPrefix("~/") || safePath.hasPrefix("~\\") { return safePath }
        return URL(fileURLWithPath: safePath).lastPathComponent
    }

    static func singleLine(_ value: String) -> String {
        redact(value)
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
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
            return .rosettaUnavailable(path: executablePath, details: excerpt)
        }

        if lowercased.contains("library not loaded")
            || lowercased.contains("dyld")
            || lowercased.contains("dylib")
            || lowercased.contains("symbol not found")
            || lowercased.contains("image not found") {
            return .runtimeLibraryFailure(path: executablePath, details: excerpt)
        }

        if let status {
            return .processNonzero(path: executablePath, status: status, details: excerpt)
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

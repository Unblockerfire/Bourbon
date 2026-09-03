//
//  BottleWineLifecycle.swift
//  WhiskyKit
//

import Foundation
import os.log

/// Prefix-scoped ownership information for Wine work.
///
/// Wine deliberately daemonizes several processes (including wineserver and Windows
/// services), so a macOS parent PID is not an ownership boundary.  The prefix is.
public struct BottleWineLifecycleSnapshot: Equatable, Sendable {
    public let bottleIdentifier: String
    public let prefixIdentifier: String
    public let launchPID: Int32?
    public let wineserverIdentifier: String
    public let terminationReason: String?
    public let cleanupResult: String?
}

public final class BottleWineLifecycle: @unchecked Sendable {
    public static let shared = BottleWineLifecycle()

    private struct Entry {
        var launchPID: Int32?
        var wineserverIdentifier: String
        var terminationReason: String?
        var cleanupResult: String?
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public func registerLaunch(bottle: Bottle, pid: Int32, wineserver: URL) {
        let key = prefixKey(for: bottle)
        lock.lock()
        var entry = entries[key] ?? Entry(
            launchPID: nil,
            wineserverIdentifier: wineserver.lastPathComponent,
            terminationReason: nil,
            cleanupResult: nil
        )
        entry.launchPID = pid
        entry.wineserverIdentifier = wineserver.lastPathComponent
        // A new launch must not inherit a completed cleanup from an earlier run.
        entry.terminationReason = nil
        entry.cleanupResult = nil
        entries[key] = entry
        lock.unlock()
        record(bottle: bottle, event: "launch", detail: "launch_pid=\(pid) wineserver=\(wineserver.lastPathComponent)")
    }

    public func beginCleanup(bottle: Bottle, reason: String, wineserver: URL) {
        let key = prefixKey(for: bottle)
        lock.lock()
        var entry = entries[key] ?? Entry(
            launchPID: nil,
            wineserverIdentifier: wineserver.lastPathComponent,
            terminationReason: nil,
            cleanupResult: nil
        )
        entry.terminationReason = safe(reason)
        entry.wineserverIdentifier = wineserver.lastPathComponent
        entry.cleanupResult = "started"
        entries[key] = entry
        lock.unlock()
        record(
            bottle: bottle,
            event: "cleanup.started",
            detail: "reason=\(safe(reason)) wineserver=\(wineserver.lastPathComponent)"
        )
    }

    public func finishCleanup(bottle: Bottle, result: String) {
        let key = prefixKey(for: bottle)
        lock.lock()
        guard var entry = entries[key] else {
            lock.unlock()
            return
        }
        entry.cleanupResult = safe(result)
        entries[key] = entry
        lock.unlock()
        record(bottle: bottle, event: "cleanup.finished", detail: "result=\(safe(result))")
    }

    public func snapshot(for bottle: Bottle) -> BottleWineLifecycleSnapshot? {
        lock.lock()
        let entry = entries[prefixKey(for: bottle)]
        lock.unlock()
        guard let entry else { return nil }
        return BottleWineLifecycleSnapshot(
            bottleIdentifier: bottle.url.lastPathComponent,
            prefixIdentifier: prefixKey(for: bottle),
            launchPID: entry.launchPID,
            wineserverIdentifier: entry.wineserverIdentifier,
            terminationReason: entry.terminationReason,
            cleanupResult: entry.cleanupResult
        )
    }

    /// A nonzero launcher exit is expected only when Bourbon deliberately stopped this
    /// Bottle's prefix. The reason is scoped to the current launch above.
    public func hasIntentionalTermination(for bottle: Bottle) -> Bool {
        guard let reason = snapshot(for: bottle)?.terminationReason else { return false }
        return Self.intentionalTerminationReasons.contains(reason)
    }

    private static let intentionalTerminationReasons: Set<String> = [
        "application_termination",
        "bottle_deleted",
        "bottle_terminated",
        "creation_cancelled",
        "installer_cancelled",
        "program_launch_cancelled",
        "program_terminated"
    ]

    private func prefixKey(for bottle: Bottle) -> String {
        // UUID-only bottle directories are safe to include in diagnostics; never log a user path.
        bottle.url.lastPathComponent
    }

    private func safe(_ value: String) -> String {
        WineDiagnosticSanitizer.singleLine(WineDiagnosticSanitizer.redact(value))
    }

    private func record(bottle: Bottle, event: String, detail: String) {
        // swiftlint:disable:next line_length
        Logger.wineKit.notice("wine.prefix.lifecycle \(event, privacy: .public) bottle_uuid=\(bottle.url.lastPathComponent, privacy: .public) wineprefix_id=\(self.prefixKey(for: bottle), privacy: .public) \(detail, privacy: .public)")
    }
}

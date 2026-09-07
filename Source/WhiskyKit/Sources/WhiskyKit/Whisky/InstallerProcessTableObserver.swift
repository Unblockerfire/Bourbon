//
//  InstallerProcessTableObserver.swift
//  WhiskyKit
//

import Foundation
import os.log

/// Immutable data needed to inspect an installer's prefix-scoped macOS processes.
/// The prefix path is used only for in-memory process attribution and is never logged.
public struct InstallerLifecycleObservationRequest: Sendable, Equatable {
    public let prefixPath: String
    public let targetExecutableName: String
    public let lifecycle: BottleWineLifecycleSnapshot?

    public init(prefixPath: String, targetExecutableName: String, lifecycle: BottleWineLifecycleSnapshot?) {
        self.prefixPath = prefixPath
        self.targetExecutableName = targetExecutableName
        self.lifecycle = lifecycle
    }
}

public enum InstallerProcessTableStatus: String, Equatable, Sendable {
    case complete
    case timedOut
    case failed
}

struct InstallerProcessTableAcquisition: Sendable, Equatable {
    let scopedLines: [String]
    let status: InstallerProcessTableStatus
}

/// Reads the process table away from the UI actor. `ps -E` is intentionally retained:
/// WINEPREFIX is the reliable ownership boundary for Wine processes that can reparent.
struct InstallerProcessTableObserver: Sendable {
    private let acquire: @Sendable (InstallerLifecycleObservationRequest) async -> InstallerProcessTableAcquisition

    init() {
        self.acquire = { request in
            await Self.acquireSystemProcessTable(for: request)
        }
    }

    init(
        acquire: @escaping @Sendable (InstallerLifecycleObservationRequest) async -> InstallerProcessTableAcquisition
    ) {
        self.acquire = acquire
    }

    func observe(_ request: InstallerLifecycleObservationRequest) async -> InstallerLifecycleObservation {
        let acquisition = await acquire(request)
        let lifecycle = request.lifecycle

        guard acquisition.status == .complete else {
            Logger.wineKit.warning(
                "installer.lifecycle.process_table status=\(acquisition.status.rawValue, privacy: .public)"
            )
            return InstallerLifecycleObservation(
                launcherPID: lifecycle?.launchPID,
                launcherIsRunning: lifecycle?.launchPID != nil,
                targetProcessIsRunning: false,
                childWineProcessCount: 0,
                wineDebuggerIsRunning: false,
                processTableStatus: acquisition.status
            )
        }

        let scopedLines = acquisition.scopedLines
        let launcherPID = lifecycle?.launchPID
        let launcherIsRunning = launcherPID.map { pid in
            scopedLines.contains { $0.split(whereSeparator: { $0.isWhitespace }).first == "\(pid)" }
        } ?? false
        let target = request.targetExecutableName.lowercased()
        let targetIsRunning = scopedLines.contains { $0.localizedCaseInsensitiveContains(target) }
        let childWineProcesses = scopedLines.filter { line in
            let lowercased = line.lowercased()
            return lowercased.contains("wine") && !lowercased.contains("winedbg")
        }.count
        let wineDebuggerIsRunning = scopedLines.contains { $0.lowercased().contains("winedbg") }

        return InstallerLifecycleObservation(
            launcherPID: launcherPID,
            launcherIsRunning: launcherIsRunning,
            targetProcessIsRunning: targetIsRunning,
            childWineProcessCount: childWineProcesses,
            wineDebuggerIsRunning: wineDebuggerIsRunning,
            processTableStatus: acquisition.status
        )
    }

    private static func acquireSystemProcessTable(
        for request: InstallerLifecycleObservationRequest
    ) async -> InstallerProcessTableAcquisition {
        await InstallerProcessTableCommand(
            executableURL: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-axE", "-o", "pid=,ppid=,state=,command="],
            matchingPrefix: request.prefixPath,
            timeout: .seconds(3)
        ).collect()
    }
}

/// A bounded, streaming subprocess reader. It never waits for child termination
/// before draining stdout, so verbose `ps -axE` output cannot fill the pipe.
final class InstallerProcessTableCommand: @unchecked Sendable {
    private let executableURL: URL
    private let arguments: [String]
    private let matchingPrefix: String
    private let timeout: Duration
    private let state = State()

    init(executableURL: URL, arguments: [String], matchingPrefix: String, timeout: Duration) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.matchingPrefix = matchingPrefix
        self.timeout = timeout
    }

    func collect() async -> InstallerProcessTableAcquisition {
        await withCheckedContinuation { continuation in
            let stdout = Pipe()
            let stderr = Pipe()
            let collector = ScopedProcessLineCollector(matchingPrefix: matchingPrefix)
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr
            state.prepare(process: process, continuation: continuation, collector: collector)

            stdout.fileHandleForReading.readabilityHandler = { handle in
                collector.consume(handle.availableData)
            }
            stderr.fileHandleForReading.readabilityHandler = { handle in
                // Drain stderr too. It is intentionally not retained because it may contain host details.
                _ = handle.availableData
            }
            process.terminationHandler = { [weak self] _ in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                collector.consumeRemaining(from: stdout.fileHandleForReading)
                self?.state.complete(status: .complete)
            }

            do {
                try process.run()
                Task.detached(priority: .utility) { [weak self] in
                    guard let self else { return }
                    try? await Task.sleep(for: self.timeout)
                    self.state.timeoutIfStillRunning()
                }
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                state.complete(status: .failed)
            }
        }
    }

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var continuation: CheckedContinuation<InstallerProcessTableAcquisition, Never>?
        private var collector: ScopedProcessLineCollector?
        private var completed = false

        func prepare(
            process: Process,
            continuation: CheckedContinuation<InstallerProcessTableAcquisition, Never>,
            collector: ScopedProcessLineCollector
        ) {
            lock.lock()
            self.process = process
            self.continuation = continuation
            self.collector = collector
            lock.unlock()
        }

        func timeoutIfStillRunning() {
            lock.lock()
            let shouldTimeout = !completed && (process?.isRunning ?? false)
            let process = self.process
            lock.unlock()
            guard shouldTimeout else { return }
            process?.terminate()
            complete(status: .timedOut)
        }

        func complete(status: InstallerProcessTableStatus) {
            lock.lock()
            guard !completed, let continuation, let collector else {
                lock.unlock()
                return
            }
            completed = true
            self.continuation = nil
            lock.unlock()
            continuation.resume(
                returning: InstallerProcessTableAcquisition(
                    scopedLines: collector.finish(),
                    status: status
                )
            )
        }
    }
}

private final class ScopedProcessLineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let matchingPrefix: String
    private var buffered = Data()
    private var lines: [String] = []

    init(matchingPrefix: String) {
        self.matchingPrefix = "WINEPREFIX=\(matchingPrefix)"
    }

    func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffered.append(data)
        consumeCompleteLinesLocked()
        lock.unlock()
    }

    func consumeRemaining(from handle: FileHandle) {
        if let data = try? handle.readToEnd() {
            consume(data)
        }
    }

    func finish() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        if !buffered.isEmpty, let line = String(data: buffered, encoding: .utf8) {
            appendIfScopedLocked(line)
        }
        buffered.removeAll(keepingCapacity: false)
        return lines
    }

    private func consumeCompleteLinesLocked() {
        while let newline = buffered.firstIndex(of: 0x0A) {
            let lineData = buffered.prefix(upTo: newline)
            buffered.removeSubrange(...newline)
            if let line = String(data: lineData, encoding: .utf8) {
                appendIfScopedLocked(line)
            }
        }
    }

    private func appendIfScopedLocked(_ line: String) {
        guard line.localizedCaseInsensitiveContains(matchingPrefix) else { return }
        lines.append(line)
    }
}

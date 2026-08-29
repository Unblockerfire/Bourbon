//
//  Process+Extensions.swift
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
import os.log

public enum ProcessOutput: Hashable {
    case started(Process)
    case message(String)
    case error(String)
    case terminated(Process)
}

public extension Process {
    /// Run the process returning a stream output
    func runStream(name: String, fileHandle: FileHandle?) throws -> AsyncStream<ProcessOutput> {
        let stream = makeStream(name: name, fileHandle: fileHandle)
        self.logProcessInfo(name: name)
        fileHandle?.writeInfo(for: self)
        try run()
        return stream
    }

    /// Run the process without piping stdout/stderr through Swift.
    func runUncaptured(name: String, fileHandle: FileHandle?) throws -> AsyncStream<ProcessOutput> {
        let stream = makeUncapturedStream(name: name, fileHandle: fileHandle)
        self.logProcessInfo(name: name)
        fileHandle?.writeInfo(for: self)
        try run()
        return stream
    }

    private func makeStream(name: String, fileHandle: FileHandle?) -> AsyncStream<ProcessOutput> {
        let pipe = Pipe()
        let errorPipe = Pipe()
        let capture = ProcessDiagnosticCapture()
        standardOutput = pipe
        standardError = errorPipe

        return AsyncStream<ProcessOutput> { continuation in
            configureCancellation(for: continuation)

            continuation.yield(.started(self))

            pipe.fileHandleForReading.readabilityHandler = { pipe in
                guard let line = pipe.nextLine() else { return }
                continuation.yield(.message(line))
                capture.record(line, channel: "stdout", fileHandle: fileHandle)
            }

            errorPipe.fileHandleForReading.readabilityHandler = { pipe in
                guard let line = pipe.nextLine() else { return }
                continuation.yield(.error(line))
                capture.record(line, channel: "stderr", fileHandle: fileHandle)
            }

            terminationHandler = { (process: Process) in
                do {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    if let data = try pipe.fileHandleForReading.readToEnd(),
                       let finalOutput = String(data: data, encoding: .utf8), !finalOutput.isEmpty {
                        continuation.yield(.message(finalOutput))
                        capture.record(finalOutput, channel: "stdout", fileHandle: fileHandle)
                    }
                    if let data = try errorPipe.fileHandleForReading.readToEnd(),
                       let finalError = String(data: data, encoding: .utf8), !finalError.isEmpty {
                        continuation.yield(.error(finalError))
                        capture.record(finalError, channel: "stderr", fileHandle: fileHandle)
                    }
                    process.logTermination(name: name, fileHandle: fileHandle)
                    if process.terminationStatus != 0 {
                        capture.logFailureSummary(
                            name: name,
                            status: process.terminationStatus,
                            fileHandle: fileHandle
                        )
                    }
                    try fileHandle?.close()
                } catch {
                    Logger.wineKit.error("Error while clearing data: \(error)")
                }

                continuation.yield(.terminated(process))
                continuation.finish()
            }
        }
    }

    private func configureCancellation(for continuation: AsyncStream<ProcessOutput>.Continuation) {
        continuation.onTermination = { termination in
            switch termination {
            case .finished:
                break
            case .cancelled:
                guard self.isRunning else { return }
                self.terminate()
            @unknown default:
                break
            }
        }
    }

    private func makeUncapturedStream(name: String, fileHandle: FileHandle?) -> AsyncStream<ProcessOutput> {
        AsyncStream<ProcessOutput> { continuation in
            continuation.onTermination = { termination in
                switch termination {
                case .finished:
                    break
                case .cancelled:
                    guard self.isRunning else { return }
                    self.terminate()
                @unknown default:
                    break
                }
            }

            continuation.yield(.started(self))

            terminationHandler = { (process: Process) in
                process.logTermination(name: name, fileHandle: fileHandle)
                do {
                    try fileHandle?.close()
                } catch {
                    Logger.wineKit.error("Error while closing log: \(error)")
                }
                continuation.yield(.terminated(process))
                continuation.finish()
            }
        }
    }

    private func logTermination(name: String, fileHandle: FileHandle?) {
        let reason: String
        switch terminationReason {
        case .exit:
            reason = "exit"
        case .uncaughtSignal:
            reason = "uncaughtSignal"
        @unknown default:
            reason = "unknown"
        }
        let message = """
        [BourbonWine Diagnostic] Process terminated
        Name: \(name)
        Termination status: \(terminationStatus)
        Termination reason: \(reason)

        """
        if terminationStatus == 0 {
            Logger.wineKit.info(
                "\(message, privacy: .public)"
            )
        } else {
            Logger.wineKit.warning(
                "\(message, privacy: .public)"
            )
        }
        fileHandle?.write(line: message)
    }

    private func logProcessInfo(name: String) {
        Logger.wineKit.info("Running process \(name)")

        if let arguments = arguments {
            let safeArguments = WineDiagnosticSanitizer.redact(arguments.joined(separator: " "))
            Logger.wineKit.info("Arguments: `\(safeArguments, privacy: .public)`")
        }
        if let executableURL = executableURL {
            Logger.wineKit.info("Executable: `\(executableURL.path(percentEncoded: false))`")
        }
        if let directory = currentDirectoryURL {
            Logger.wineKit.info("Directory: `\(directory.path(percentEncoded: false))`")
        }
        if let environment = environment {
            let runtimeEnvironment = WineDiagnosticSanitizer.filteredRuntimeEnvironment(environment)
            let safeEnvironment = WineDiagnosticSanitizer.redactEnvironment(runtimeEnvironment)
            Logger.wineKit.info("Environment: \(safeEnvironment, privacy: .public)")
        }
    }
}

private final class ProcessDiagnosticCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var combinedOutput = ""

    func record(_ value: String, channel: String, fileHandle: FileHandle?) {
        guard !value.isEmpty else { return }
        let safeValue = WineDiagnosticSanitizer.redact(value)
        let message = "[BourbonWine Diagnostic][\(channel)] \(safeValue)"

        lock.lock()
        combinedOutput.append("[\(channel)] \(safeValue)")
        if combinedOutput.count > WineDiagnosticSanitizer.excerptLimit * 2 {
            combinedOutput = String(combinedOutput.suffix(WineDiagnosticSanitizer.excerptLimit))
        }
        fileHandle?.write(line: message)
        lock.unlock()

        if channel == "stderr" {
            Logger.wineKit.warning("\(message, privacy: .public)")
        } else {
            Logger.wineKit.info("\(message, privacy: .public)")
        }
    }

    func logFailureSummary(name: String, status: Int32, fileHandle: FileHandle?) {
        lock.lock()
        let output = combinedOutput
        let excerpt = WineDiagnosticSanitizer.excerpt(from: output)
        let message = """
        [BourbonWine Diagnostic] Failed process output excerpt
        Name: \(name)
        Termination status: \(status)
        Safe stdout/stderr excerpt:
        \(excerpt)

        """
        fileHandle?.write(line: message)
        lock.unlock()
        Logger.wineKit.error("\(message, privacy: .public)")
    }
}

extension FileHandle {
    func nextLine() -> String? {
        guard let line = String(data: availableData, encoding: .utf8) else { return nil }
        if !line.isEmpty {
            return line
        } else {
            return nil
        }
    }
}

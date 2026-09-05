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
        #if DEBUG
        self.logProcessInfo(name: name)
        fileHandle?.writeInfo(for: self)
        #endif
        self.logRunBoundary(name: name, launchMode: "captured", fileHandle: fileHandle)
        try run()
        return stream
    }

    /// Run the process without piping stdout/stderr through Swift.
    func runUncaptured(name: String, fileHandle: FileHandle?) throws -> AsyncStream<ProcessOutput> {
        let stream = makeUncapturedStream(name: name, fileHandle: fileHandle)
        #if DEBUG
        self.logProcessInfo(name: name)
        fileHandle?.writeInfo(for: self)
        #endif
        self.logRunBoundary(name: name, launchMode: "normalGUI", fileHandle: fileHandle)
        try run()
        return stream
    }

    private func makeStream(name: String, fileHandle: FileHandle?) -> AsyncStream<ProcessOutput> {
        let pipe = Pipe()
        let errorPipe = Pipe()
        standardOutput = pipe
        standardError = errorPipe

        return AsyncStream<ProcessOutput> { continuation in
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

            pipe.fileHandleForReading.readabilityHandler = { pipe in
                guard let line = pipe.nextLine() else { return }
                continuation.yield(.message(line))
                guard !line.isEmpty else { return }
                #if DEBUG
                Logger.wineKit.info("[BourbonWine Debug][stdout] \(line, privacy: .public)")
                fileHandle?.write(line: "[BourbonWine Debug][stdout] \(line)")
                #endif
            }

            errorPipe.fileHandleForReading.readabilityHandler = { pipe in
                guard let line = pipe.nextLine() else { return }
                continuation.yield(.error(line))
                guard !line.isEmpty else { return }
                #if DEBUG
                Logger.wineKit.warning("[BourbonWine Debug][stderr] \(line, privacy: .public)")
                fileHandle?.write(line: "[BourbonWine Debug][stderr] \(line)")
                #endif
            }

            terminationHandler = { (process: Process) in
                do {
                    _ = try pipe.fileHandleForReading.readToEnd()
                    _ = try errorPipe.fileHandleForReading.readToEnd()
                    #if DEBUG
                    process.logTermination(name: name, fileHandle: fileHandle)
                    #endif
                    try fileHandle?.close()
                } catch {
                    Logger.wineKit.error("Error while clearing data: \(error)")
                }

                continuation.yield(.terminated(process))
                continuation.finish()
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
                #if DEBUG
                process.logTermination(name: name, fileHandle: fileHandle)
                #endif
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

    #if DEBUG
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
        [BourbonWine Debug] Process terminated
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
            Logger.wineKit.info("Arguments: `\(arguments.joined(separator: " "))`")
        }
        if let executableURL = executableURL {
            Logger.wineKit.info("Executable: `\(executableURL.path(percentEncoded: false))`")
        }
        if let directory = currentDirectoryURL {
            Logger.wineKit.info("Directory: `\(directory.path(percentEncoded: false))`")
        }
        if let environment = environment {
            Logger.wineKit.info("Environment: \(environment)")
        }
    }
    #endif

    private func logRunBoundary(name: String, launchMode: String, fileHandle: FileHandle?) {
        let executable = executableURL?.path(percentEncoded: false) ?? "<nil>"
        let processArguments = arguments ?? []
        let directory = currentDirectoryURL?.path(percentEncoded: false) ?? "<nil>"
        let processEnvironment = Self.diagnosticEnvironment(environment ?? [:])
        let message = """
        [BourbonWine Diagnostic] Process.run boundary
        Name: \(name)
        Process executableURL: \(executable)
        Process argv: \(processArguments)
        Process working directory: \(directory)
        Process environment:
        \(processEnvironment)
        Standard input attachment: \(Self.attachmentDescription(standardInput))
        Standard output attachment: \(Self.attachmentDescription(standardOutput))
        Standard error attachment: \(Self.attachmentDescription(standardError))
        Termination handler attached: \(terminationHandler != nil)
        Launch API: Foundation.Process.run
        Launch mode: \(launchMode)

        """

        Logger.wineKit.info("\(message, privacy: .public)")
        fileHandle?.write(line: message)
    }

    private static func attachmentDescription(_ attachment: Any?) -> String {
        guard let attachment else { return "<nil>" }
        return String(describing: type(of: attachment))
    }

    private static func diagnosticEnvironment(_ environment: [String: String]) -> String {
        guard !environment.isEmpty else { return "<empty>" }
        return environment
            .sorted { $0.key < $1.key }
            .map { key, value in
                let sensitiveFragments = ["TOKEN", "PASSWORD", "SECRET", "CREDENTIAL", "AUTH"]
                let isSensitive = sensitiveFragments.contains { key.uppercased().contains($0) }
                return "\(key)=\(isSensitive ? "<redacted>" : value)"
            }
            .joined(separator: "\n")
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

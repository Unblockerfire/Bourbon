// swiftlint:disable file_length

//
//  Wine.swift
//  Whisky
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

import Darwin
import Foundation
import os.log

// swiftlint:disable:next type_body_length
public class Wine {
    private enum WineProcessOutputMode {
        case captured
    }

    private enum CustomWineSettings {
        static let rootEnvironmentKey = "WHISKY_CUSTOM_WINE_ROOT"
        static let wineEnvironmentKey = "WHISKY_CUSTOM_WINE"
        static let wineserverEnvironmentKey = "WHISKY_CUSTOM_WINESERVER"

        static let rootDefaultsKey = "whiskyCustomWineRoot"
        static let wineDefaultsKey = "whiskyCustomWinePath"
        static let wineserverDefaultsKey = "whiskyCustomWineserverPath"

        static var root: String? {
            value(environmentKey: rootEnvironmentKey, defaultsKey: rootDefaultsKey)
        }

        static var wine: String? {
            value(environmentKey: wineEnvironmentKey, defaultsKey: wineDefaultsKey)
        }

        static var wineserver: String? {
            value(environmentKey: wineserverEnvironmentKey, defaultsKey: wineserverDefaultsKey)
        }

        static var configuredEnvironment: [String: String] {
            [
                rootEnvironmentKey: root,
                wineEnvironmentKey: wine,
                wineserverEnvironmentKey: wineserver
            ].compactMapValues { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
        }

        static var startupDebugMessage: String {
            let environment = ProcessInfo.processInfo.environment
            let defaults = UserDefaults.standard.dictionaryRepresentation()
            let runner = CustomWineRunner.active
            let whiskyEnvironment = environment
                .filter { key, _ in key.hasPrefix("WHISKY_") }
                .sorted { $0.key < $1.key }
            let whiskyDefaults = defaults
                .filter { key, _ in key.hasPrefix("WHISKY_") || key.hasPrefix("whiskyCustomWine") }
                .sorted { $0.key < $1.key }

            return """

            [BourbonWine Debug] App startup custom Wine configuration
            Visible WHISKY_* process environment:
            \(format(values: whiskyEnvironment))
            Visible custom Wine UserDefaults:
            \(format(values: whiskyDefaults.map { key, value in (key, String(describing: value)) }))
            Resolved custom Wine root: \(root ?? "<not set>")
            Resolved custom Wine executable: \(runner?.wine.path(percentEncoded: false) ?? "<bundled>")
            Resolved custom wineserver: \(runner?.wineserver.path(percentEncoded: false) ?? "<bundled>")

            """
        }

        private static func value(environmentKey: String, defaultsKey: String) -> String? {
            let environment = ProcessInfo.processInfo.environment
            let defaults = UserDefaults.standard

            return nonEmpty(environment[environmentKey])
                ?? nonEmpty(defaults.string(forKey: environmentKey))
                ?? nonEmpty(defaults.string(forKey: defaultsKey))
        }

        private static func nonEmpty(_ value: String?) -> String? {
            guard let value, !value.isEmpty else { return nil }
            return value
        }

        private static func format(values: [(key: String, value: String)]) -> String {
            guard !values.isEmpty else { return "<none>" }
            return values
                .map { key, value in "\(key)=\(value)" }
                .joined(separator: "\n")
        }
    }

    private struct CustomWineRunner {
        let wine: URL
        let wineserver: URL

        var binFolder: URL {
            wine.deletingLastPathComponent()
        }

        static var active: CustomWineRunner? {
            guard let rootValue = CustomWineSettings.root else {
                return nil
            }

            let root = URL(fileURLWithPath: expandTilde(in: rootValue))
            let wine = URL(
                fileURLWithPath: expandTilde(
                    in: CustomWineSettings.wine ?? root.appending(path: "wine").path
                )
            )
            let wineserver = URL(
                fileURLWithPath: expandTilde(
                    in: CustomWineSettings.wineserver
                        ?? root.appending(path: "server").appending(path: "wineserver").path
                )
            )

            return CustomWineRunner(wine: wine, wineserver: wineserver)
        }

        private static func expandTilde(in path: String) -> String {
            NSString(string: path).expandingTildeInPath
        }
    }

    /// URL to the installed `DXVK` folder
    private static let dxvkFolder: URL = WhiskyWineInstaller.libraryFolder.appending(path: "DXVK")
    /// URL to the installed Wine `lib` directory.
    private static let wineLibraryFolder: URL = WhiskyWineInstaller.libraryFolder
        .appending(path: "Wine")
        .appending(path: "lib")

    /// Local custom Wine runner for testing TikFinity with a Wine10 build tree.
    /// Enable with `WHISKY_CUSTOM_WINE_ROOT=/path/to/build`; normal WhiskyWine remains the default.
    private static var customWineRunner: CustomWineRunner? {
        CustomWineRunner.active
    }

    /// Path to the selected `wine` binary.
    public static var wineBinary: URL {
        resolveWineExecutable()
    }

    /// Resolve the Wine launcher used by every Bourbon Wine command.
    public static func resolveWineExecutable() -> URL {
        customWineRunner?.wine ?? RuntimeWineBinary.resolve(in: WhiskyWineInstaller.binFolder)
    }

    /// Path to the selected `wineserver` binary.
    private static var wineserverBinary: URL {
        customWineRunner?.wineserver ?? WhiskyWineInstaller.binFolder.appending(path: "wineserver")
    }

    /// Directory that should be placed first on PATH for Wine helper programs.
    public static var wineBinFolder: URL {
        customWineRunner?.binFolder ?? WhiskyWineInstaller.binFolder
    }

    public static func logCustomWineStartupEnvironment() {
        #if DEBUG
        Logger.wineKit.info("\(CustomWineSettings.startupDebugMessage, privacy: .public)")
        #endif
    }

    /// Run a process on a executable file given by the `executableURL`
    private static func runProcess(
        name: String? = nil, args: [String], environment: [String: String], executableURL: URL, directory: URL? = nil,
        outputMode: WineProcessOutputMode = .captured,
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = args
        process.currentDirectoryURL = directory ?? executableURL.deletingLastPathComponent()
        process.environment = environment
        process.qualityOfService = .userInitiated

        let processName = name ?? args.joined(separator: " ")
        debugLogWineLaunch(
            name: processName,
            args: args,
            environment: environment,
            executableURL: executableURL,
            workingDirectory: process.currentDirectoryURL,
            fileHandle: fileHandle
        )

        do {
            switch outputMode {
            case .captured:
                return try process.runStream(name: processName, fileHandle: fileHandle)
            }
        } catch {
            debugLogProcessLaunchError(
                error,
                name: processName,
                executableURL: executableURL,
                fileHandle: fileHandle
            )
            throw error
        }
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    private static func runWineProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:],
        directory: URL? = nil,
        outputMode: WineProcessOutputMode = .captured,
        executableURL: URL? = nil,
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        let selectedExecutable = executableURL ?? resolveWineExecutable()
        return try runProcess(
            name: name, args: args, environment: environment, executableURL: selectedExecutable,
            directory: directory, outputMode: outputMode, fileHandle: fileHandle
        )
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    private static func runWineserverProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:],
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment, executableURL: wineserverBinary,
            fileHandle: fileHandle
        )
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    public static func runWineProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicaitonInfo()
        fileHandle.writeInfo(for: bottle)

        return try runWineProcess(
            name: name, args: args,
            environment: constructWineEnvironment(for: bottle, environment: environment),
            fileHandle: fileHandle
        )
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    public static func runWineserverProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicaitonInfo()
        fileHandle.writeInfo(for: bottle)

        return try runWineserverProcess(
            name: name, args: args,
            environment: constructWineServerEnvironment(for: bottle, environment: environment),
            fileHandle: fileHandle
        )
    }

    // Execute a program with Wine, using direct execution for Windows installer binaries.
    // swiftlint:disable:next function_body_length
    public static func runProgram(
        at url: URL,
        args: [String] = [],
        bottle: Bottle,
        environment: [String: String] = [:],
        progress: (@Sendable (CompatibilityProgress) -> Void)? = nil
    ) async throws {
        if bottle.settings.dxvk {
            try enableDXVK(bottle: bottle)
        }

        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicaitonInfo()
        fileHandle.writeInfo(for: bottle)

        let diagnostics = ProgramLaunchDiagnostics.inspect(url: url)
        logProgramLaunchDiagnostics(url: url, diagnostics: diagnostics, fileHandle: fileHandle)
        let launchPlan = try await CompatibilityManager.shared.launchPlan(
            for: url,
            bottle: bottle,
            arguments: args,
            progress: progress
        )
        logCompatibilityLaunchPlan(launchPlan, fileHandle: fileHandle)
        let launchDiagnostics = logFinalLaunchDiagnostics(
            for: launchPlan,
            originalURL: url,
            fileHandle: fileHandle
        )
        let outputMode = outputMode(for: launchPlan, diagnostics: launchDiagnostics)
        logProgramOutputMode(outputMode, fileHandle: fileHandle)

        var output: [String] = []
        var terminationStatus: Int32 = 0

        let stream = try runWineProcess(
            name: launchPlan.executableURL.lastPathComponent,
            args: runProgramArguments(for: launchPlan.executableURL, args: launchPlan.arguments),
            environment: constructWineEnvironment(for: bottle, environment: environment),
            directory: launchPlan.workingDirectory,
            outputMode: outputMode,
            fileHandle: fileHandle
        )

        do {
            for await result in stream {
                try Task.checkCancellation()
                switch result {
                case .started(let process):
                    // Do not infer ownership from Process.parent. Wine may reparent
                    // steamservice/steamwebhelper to launchd; wineserver + WINEPREFIX
                    // remains the bottle-scoped ownership boundary.
                    BottleWineLifecycle.shared.registerLaunch(
                        bottle: bottle,
                        pid: process.processIdentifier,
                        wineserver: wineserverBinary
                    )
                case .message(let message), .error(let message):
                    output.append(message)
                case .terminated(let process):
                    terminationStatus = process.terminationStatus
                }
            }
        } catch is CancellationError {
            try? await stopBottleProcesses(bottle: bottle, reason: "program_launch_cancelled")
            throw CancellationError()
        } catch {
            try? await stopBottleProcesses(bottle: bottle, reason: "program_launch_failed")
            throw error
        }

        guard terminationStatus == 0 else {
            if BottleWineLifecycle.shared.hasIntentionalTermination(for: bottle) {
                // swiftlint:disable:next line_length
                Logger.wineKit.info("Program launcher ended after intentional prefix cleanup for \(url.lastPathComponent, privacy: .public).")
                throw ProgramLaunchIntentionalTermination(url: url)
            }
            try? await stopBottleProcesses(bottle: bottle, reason: "program_launch_exit_\(terminationStatus)")
            let rawOutput = output.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            Logger.wineKit.warning(
                """
                Failed to launch \(url.lastPathComponent, privacy: .public).
                \(diagnostics.summary, privacy: .public)
                """
            )
            throw ProgramLaunchError(
                url: url,
                diagnostics: launchDiagnostics,
                output: rawOutput.isEmpty ? "" : WineDiagnosticSanitizer.excerpt(from: rawOutput)
            )
        }
    }

    public static func generateRunCommand(
        at url: URL, bottle: Bottle, args: String, environment: [String: String]
    ) -> String {
        var wineCmd = generateRunProgramCommand(at: url, args: args)
        let env = constructWineEnvironment(for: bottle, environment: environment)
        for environment in env {
            wineCmd = "\(environment.key)=\"\(environment.value)\" " + wineCmd
        }

        return wineCmd
    }

    public static func generateTerminalEnvironmentCommand(bottle: Bottle) -> String {
        let wineCommand = wineBinary.esc
        var cmd = """
        export PATH=\"\(wineBinFolder.path):$PATH\"
        export WINE=\"\(wineBinary.path)\"
        alias wine=\"\(wineCommand)\"
        alias winecfg=\"\(wineCommand) winecfg\"
        alias msiexec=\"\(wineCommand) msiexec\"
        alias regedit=\"\(wineCommand) regedit\"
        alias regsvr32=\"\(wineCommand) regsvr32\"
        alias wineboot=\"\(wineCommand) wineboot\"
        alias wineconsole=\"\(wineCommand) wineconsole\"
        alias winedbg=\"\(wineCommand) winedbg\"
        alias winefile=\"\(wineCommand) winefile\"
        alias winepath=\"\(wineCommand) winepath\"
        """
        if customWineRunner == nil {
            cmd += """

            export DYLD_LIBRARY_PATH=\"\(wineLibraryFolder.path):${DYLD_LIBRARY_PATH:-}\"
            export DYLD_FALLBACK_LIBRARY_PATH=\"\(wineLibraryFolder.path):${DYLD_FALLBACK_LIBRARY_PATH:-}\"
            """
        }

        let env = constructWineEnvironment(for: bottle, environment: constructWineEnvironment(for: bottle))
        for environment in env {
            cmd += "\nexport \(environment.key)=\"\(environment.value)\""
        }

        return cmd
    }

    /// Run a `wineserver` command with the given arguments and return the output result
    private static func runWineserver(_ args: [String], bottle: Bottle) async throws -> String {
        var result: [ProcessOutput] = []

        for await output in try Self.runWineserverProcess(args: args, bottle: bottle, environment: [:]) {
            result.append(output)
        }

        return result.compactMap { output -> String? in
            switch output {
            case .started, .terminated:
                return nil
            case .message(let message), .error(let message):
                return message
            }
        }.joined()
    }

    @discardableResult
    /// Run a `wine` command with the given arguments and return the output result
    public static func runWine(
        _ args: [String], bottle: Bottle?, environment: [String: String] = [:]
    ) async throws -> String {
        try await runWineCommand(
            args,
            bottle: bottle,
            environment: environment,
            executableURL: resolveWineExecutable()
        )
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private static func runWineCommand(
        _ args: [String],
        bottle: Bottle?,
        environment: [String: String] = [:],
        phase: String? = nil,
        timeoutSeconds: TimeInterval? = nil,
        operation: BottleWineOperation? = nil,
        singleInvocation: Bool = false,
        executableURL: URL
    ) async throws -> String {
        let processReference = ProcessReference()
        if let operation, let phase {
            if singleInvocation {
                try operation.beginSingleInvocation(phase: phase, command: args)
            } else {
                operation.beginInvocation(phase: phase, command: args)
            }
        }
        if let timeoutSeconds {
            processReference.armTimeout(after: timeoutSeconds)
        }
        defer { processReference.cancelDeadline() }
        return try await withTaskCancellationHandler(operation: {
            var standardOutput: [String] = []
            var standardError: [String] = []
            var terminationStatus: Int32 = 0
            var terminationReason = "not_started"
            let fileHandle = try makeFileHandle()
            fileHandle.writeApplicaitonInfo()
            var environment = constructWineRuntimeEnvironment(environment)

            if let bottle = bottle {
                fileHandle.writeInfo(for: bottle)
                environment = constructWineEnvironment(for: bottle, environment: environment)
            }

            try Task.checkCancellation()
            let processName = phase.map { "phase=\($0) command=\(args.joined(separator: " "))" }
            for await output in try runWineProcess(
                name: processName,
                args: args,
                environment: environment,
                executableURL: executableURL,
                fileHandle: fileHandle
            ) {
                try Task.checkCancellation()
                switch output {
                case .started(let process):
                    processReference.register(process)
                    if let operation, let phase {
                        operation.register(process, phase: phase)
                    }
                    if phase == "preflight" {
                        WhiskyWineInstaller.recordRuntimeEvent(
                            "runtime.preflight.process.started",
                            detail: "pid=\(process.processIdentifier)"
                        )
                    }
                case .terminated(let process):
                    terminationStatus = process.terminationStatus
                    terminationReason = process.terminationReason.runtimeDiagnosticDescription
                    processReference.clear(process)
                    if let operation, let phase {
                        operation.processTerminated(process, phase: phase)
                    }
                    if phase == "preflight" {
                        WhiskyWineInstaller.recordRuntimeEvent(
                            "runtime.preflight.process.terminated",
                            detail: "reason=\(terminationReason) exit_status=\(terminationStatus)"
                        )
                    }
                case .message(let message):
                    standardOutput.append(message)
                case .error(let message):
                    standardError.append(message)
                }
            }

            if processReference.didTimeOut {
                throw WineCommandTimeoutError(phase: phase ?? "wine_command")
            }
            guard terminationStatus == 0 else {
                throw WineProcessError(
                    command: args,
                    status: terminationStatus,
                    standardOutput: standardOutput.joined(),
                    standardError: standardError.joined(),
                    terminationReason: terminationReason
                )
            }
            return standardOutput.joined() + standardError.joined()
        }, onCancel: {
            processReference.cancel()
            operation?.cancel(reason: "task_cancelled")
        })
    }

    public static func wineVersion() async throws -> String {
        let output = try await runWine(["--version"], bottle: nil)
        return try WineSemanticVersion.requireVersionToken(from: output)
    }

    // swiftlint:disable:next function_body_length
    public static func preflightRuntime(
        executableURL selectedExecutableURL: URL? = nil,
        operation: BottleWineOperation? = nil
    ) async throws -> WineRuntimePreflightResult {
        let executableURL = selectedExecutableURL ?? resolveWineExecutable()
        let executablePath = executableURL.path(percentEncoded: false)
        let executableContext = runtimeExecutableContext(executableURL)

        WhiskyWineInstaller.recordRuntimeEvent("runtime.preflight.started", detail: "arguments=--version")
        WhiskyWineInstaller.recordRuntimeEvent(
            "runtime.executable.resolved",
            detail: "path=\(WineDiagnosticSanitizer.redact(executablePath))"
        )
        WhiskyWineInstaller.recordRuntimeEvent(
            "runtime.executable.exists",
            detail: "value=\(executableContext.exists)"
        )
        WhiskyWineInstaller.recordRuntimeEvent(
            "runtime.executable.permissions",
            detail: "executable=\(executableContext.isExecutable) mode=\(executableContext.permissions)"
        )
        WhiskyWineInstaller.recordRuntimeEvent(
            "runtime.executable.architecture",
            detail: "value=\(executableContext.architecture)"
        )

        do {
            try validateRuntimeExecutable(executableURL)
            let output = try await runWineCommand(
                ["--version"],
                bottle: nil,
                phase: "preflight",
                timeoutSeconds: 30,
                operation: operation,
                singleInvocation: operation != nil,
                executableURL: executableURL
            )
            let version = try preflightVersion(from: output, executablePath: executablePath)
            let result = WineRuntimePreflightResult(version: version)
            WhiskyWineInstaller.recordRuntimeEvent(
                "runtime.preflight.completed",
                detail: "wine_version=\(WineDiagnosticSanitizer.singleLine(result.version))"
            )
            Logger.wineKit.info("Runtime preflight passed with Wine \(result.version, privacy: .public)")
            return result
        } catch let error as WineRuntimePreflightError {
            recordStructuredPreflightFailure(error, context: executableContext)
            recordPreflightFailure(error, executableURL: executableURL)
            throw error
        } catch let error as WineProcessError {
            let processDetails = """
            termination_reason=\(error.terminationReason)
            stdout=\(WineDiagnosticSanitizer.excerpt(from: error.standardOutput))
            stderr=\(WineDiagnosticSanitizer.excerpt(from: error.standardError))
            """
            let classifiedError = WineDiagnosticSanitizer.classifiedFailure(
                details: processDetails,
                executablePath: executablePath,
                status: error.status
            )
            recordStructuredPreflightFailure(
                classifiedError,
                context: executableContext,
                launchError: nil,
                processError: error
            )
            recordPreflightFailure(classifiedError, executableURL: executableURL)
            throw classifiedError
        } catch let error as WineCommandTimeoutError {
            let classifiedError = WineRuntimePreflightError.timedOut(
                path: executablePath,
                details: "The bounded readiness check exceeded 30 seconds during \(error.phase)."
            )
            recordStructuredPreflightFailure(classifiedError, context: executableContext)
            recordPreflightFailure(classifiedError, executableURL: executableURL)
            throw classifiedError
        } catch {
            let classifiedError = WineDiagnosticSanitizer.classifiedFailure(
                details: String(describing: error) + "\n" + error.localizedDescription,
                executablePath: executablePath
            )
            recordStructuredPreflightFailure(
                classifiedError,
                context: executableContext,
                launchError: error.localizedDescription
            )
            recordPreflightFailure(classifiedError, executableURL: executableURL)
            throw classifiedError
        }
    }

    private static func runtimeExecutableContext(_ executableURL: URL) -> RuntimeExecutableContext {
        let path = executableURL.path(percentEncoded: false)
        let fileManager = FileManager.default
        let exists = fileManager.fileExists(atPath: path)
        let attributes = try? fileManager.attributesOfItem(atPath: path)
        let permissions = (attributes?[.posixPermissions] as? NSNumber)
            .map { String(format: "%03o", $0.intValue) } ?? "unavailable"
        let architecture = exists
            ? WineDiagnosticSanitizer.singleLine(debugFileOutput(for: executableURL))
            : "unavailable"
        return RuntimeExecutableContext(
            path: WineDiagnosticSanitizer.redact(path),
            exists: exists,
            isExecutable: fileManager.isExecutableFile(atPath: path),
            permissions: permissions,
            architecture: architecture
        )
    }

    private static func recordStructuredPreflightFailure(
        _ error: WineRuntimePreflightError,
        context: RuntimeExecutableContext,
        launchError: String? = nil,
        processError: WineProcessError? = nil
    ) {
        let launch = WineDiagnosticSanitizer.singleLine(launchError ?? "none")
        let stdout = WineDiagnosticSanitizer.singleLine(
            WineDiagnosticSanitizer.excerpt(from: processError?.standardOutput ?? "")
        )
        let stderr = WineDiagnosticSanitizer.singleLine(
            WineDiagnosticSanitizer.excerpt(from: processError?.standardError ?? "")
        )
        WhiskyWineInstaller.recordRuntimeEvent(
            "runtime.preflight.failed",
            detail: """
            check=\(error.failedCheck) path=\(context.path) exists=\(context.exists) \
            executable=\(context.isExecutable) architecture=\(context.architecture) \
            launch_error=\(launch) termination_reason=\(processError?.terminationReason ?? "not_started") \
            exit_status=\(processError.map { String($0.status) } ?? "unavailable") \
            stdout=\(stdout) stderr=\(stderr)
            """
        )
    }

    private static func validateRuntimeExecutable(_ executableURL: URL) throws {
        let executablePath = executableURL.path(percentEncoded: false)
        let fileManager = FileManager.default
        let error: WineRuntimePreflightError?
        if !fileManager.fileExists(atPath: executablePath) {
            error = .executableMissing(path: executablePath)
        } else if !fileManager.isExecutableFile(atPath: executablePath) {
            error = .cannotExecute(
                path: executablePath,
                details: "The file exists but does not have executable permission."
            )
        } else {
            error = nil
        }

        if let error { throw error }
    }

    private static func preflightVersion(from output: String, executablePath: String) throws -> String {
        guard WineDiagnosticSanitizer.isValidVersionOutput(output),
              let version = try? WineSemanticVersion.requireVersionToken(from: output) else {
            throw WineRuntimePreflightError.invalidWineOutput(
                path: executablePath,
                details: WineDiagnosticSanitizer.excerpt(from: output)
            )
        }
        return version
    }

    static func recordPreflightFailure(
        _ error: WineRuntimePreflightError,
        executableURL: URL,
        logsFolder: URL? = nil
    ) {
        let safeDescription = error.unifiedLogDescription
        Logger.wineKit.error("Runtime preflight failed: \(safeDescription, privacy: .public)")

        do {
            let fileHandle = try makeFileHandle(in: logsFolder ?? Self.logsFolder)
            fileHandle.writeApplicaitonInfo()
            let environment = constructWineRuntimeEnvironment()
            debugLogWineLaunch(
                name: "phase=preflight command=--version",
                args: ["--version"],
                environment: environment,
                executableURL: executableURL,
                workingDirectory: executableURL.deletingLastPathComponent(),
                fileHandle: fileHandle
            )
            fileHandle.write(line: """

            [BourbonWine Diagnostic] Runtime preflight failure
            Phase: preflight
            Classification: \(error.diagnosticCode)
            Safe description: \(safeDescription)

            """)
            try fileHandle.close()
        } catch {
            let description = WineDiagnosticSanitizer.redact(error.localizedDescription)
            Logger.wineKit.error(
                "Failed to write runtime preflight diagnostic log: \(description, privacy: .public)"
            )
        }
    }

    @discardableResult
    public static func runBatchFile(url: URL, bottle: Bottle) async throws -> String {
        return try await runWine(["cmd", "/c", url.path(percentEncoded: false)], bottle: bottle)
    }

    public static func killBottle(bottle: Bottle) throws {
        _ = Task.detached(priority: .userInitiated) {
            try await stopBottleProcesses(bottle: bottle, reason: "bottle_terminated")
        }
    }

    public static func killProgram(program: Program, bottle: Bottle) throws {
        // A Windows program can leave daemonized services behind after its launcher
        // exits. `taskkill` only sees one Windows image; wineserver owns the complete
        // WINEPREFIX and is consequently the safe bottle-scoped stop mechanism.
        _ = Task.detached(priority: .userInitiated) {
            try await stopBottleProcesses(bottle: bottle, reason: "program_terminated")
        }
    }

    public static func enableDXVK(bottle: Bottle) throws {
        try FileManager.default.replaceDLLs(
            in: bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "system32"),
            withContentsIn: Wine.dxvkFolder.appending(path: "x64")
        )
        try FileManager.default.replaceDLLs(
            in: bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "syswow64"),
            withContentsIn: Wine.dxvkFolder.appending(path: "x32")
        )
    }

    /// Construct an environment merging the bottle values with the given values
    private static func constructWineEnvironment(
        for bottle: Bottle, environment: [String: String] = [:]
    ) -> [String: String] {
        var result = constructWineRuntimeEnvironment([
            "WINEPREFIX": bottle.url.path,
            "WINEDEBUG": "fixme-all",
            "GST_DEBUG": "1"
        ])
        bottle.settings.environmentVariables(wineEnv: &result)
        guard !environment.isEmpty else { return result }
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
    }

    /// Construct an environment merging the bottle values with the given values
    private static func constructWineServerEnvironment(
        for bottle: Bottle, environment: [String: String] = [:]
    ) -> [String: String] {
        var result = constructWineRuntimeEnvironment([
            "WINEPREFIX": bottle.url.path,
            "WINEDEBUG": "fixme-all",
            "GST_DEBUG": "1"
        ])
        guard !environment.isEmpty else { return result }
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
    }

    private static func constructWineRuntimeEnvironment(_ environment: [String: String] = [:]) -> [String: String] {
        var result: [String: String] = [
            "PATH": [
                wineBinFolder.path,
                ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            ].joined(separator: ":")
        ]

        if customWineRunner == nil {
            result["DYLD_LIBRARY_PATH"] = wineLibraryFolder.path
            result["DYLD_FALLBACK_LIBRARY_PATH"] = wineLibraryFolder.path
        } else {
            if let dyldLibraryPath = ProcessInfo.processInfo.environment["DYLD_LIBRARY_PATH"],
               !dyldLibraryPath.isEmpty {
                result["DYLD_LIBRARY_PATH"] = dyldLibraryPath
            }
            if let dyldFallbackLibraryPath = ProcessInfo.processInfo.environment["DYLD_FALLBACK_LIBRARY_PATH"],
               !dyldFallbackLibraryPath.isEmpty {
                result["DYLD_FALLBACK_LIBRARY_PATH"] = dyldFallbackLibraryPath
            }
        }

        result.merge(CustomWineSettings.configuredEnvironment, uniquingKeysWith: { $1 })

        guard !environment.isEmpty else { return result }
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
    }
}

private final class ProcessReference: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancellationRequested = false
    private var timedOut = false
    private var deadline: DispatchWorkItem?

    var didTimeOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timedOut
    }

    func armTimeout(after seconds: TimeInterval) {
        let item = DispatchWorkItem { [weak self] in
            self?.timeout()
        }
        lock.lock()
        deadline = item
        lock.unlock()
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + seconds, execute: item)
    }

    func cancelDeadline() {
        lock.lock()
        let deadline = deadline
        self.deadline = nil
        lock.unlock()
        deadline?.cancel()
    }

    func register(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldTerminate = cancellationRequested
        lock.unlock()
        if shouldTerminate { terminate(process) }
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        let process = process
        lock.unlock()
        terminate(process)
    }

    func clear(_ process: Process) {
        lock.lock()
        if self.process === process { self.process = nil }
        lock.unlock()
    }

    private func timeout() {
        lock.lock()
        timedOut = true
        cancellationRequested = true
        let process = process
        lock.unlock()
        terminate(process)
    }

    private func terminate(_ process: Process?) {
        guard let process, process.isRunning else { return }
        process.terminate()
        let processIdentifier = process.processIdentifier
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2) {
            guard process.isRunning else { return }
            Darwin.kill(processIdentifier, SIGKILL)
        }
    }
}

private struct RuntimeExecutableContext {
    let path: String
    let exists: Bool
    let isExecutable: Bool
    let permissions: String
    let architecture: String
}

private extension Process.TerminationReason {
    var runtimeDiagnosticDescription: String {
        switch self {
        case .exit: return "exit"
        case .uncaughtSignal: return "uncaught_signal"
        @unknown default: return "unknown"
        }
    }
}

public struct WineProcessError: LocalizedError {
    public let command: [String]
    public let status: Int32
    public let standardOutput: String
    public let standardError: String
    public let terminationReason: String

    public var output: String {
        standardOutput + standardError
    }

    public var errorDescription: String? {
        let excerpt = WineDiagnosticSanitizer.excerpt(from: output)
        return "Wine command failed with exit status \(status). \(excerpt)"
    }

    public var isGatekeeperBlocked: Bool {
        WineDiagnosticSanitizer.classifiedFailure(
            details: output,
            executablePath: command.first ?? "wine",
            status: status
        ).isGatekeeperBlocked
    }
}

public struct WineCommandTimeoutError: LocalizedError, Sendable {
    public let phase: String

    public var errorDescription: String? {
        "BourbonWine command timed out during \(phase)."
    }
}

extension Wine {
    // swiftlint:disable:next function_parameter_count
    static func debugLogWineLaunch(
        name: String,
        args: [String],
        environment: [String: String],
        executableURL: URL,
        workingDirectory: URL?,
        fileHandle: FileHandle?
    ) {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        let executablePath = executableURL.path(percentEncoded: false)
        let exists = fileManager.fileExists(atPath: executablePath, isDirectory: &isDirectory)
        let isExecutable = fileManager.isExecutableFile(atPath: executablePath)
        let attributes = try? fileManager.attributesOfItem(atPath: executablePath)
        let permissions = (attributes?[.posixPermissions] as? NSNumber)?.intValue
        let permissionText = permissions.map { String(format: "%03o", $0) } ?? "<unavailable>"
        let customEnvironment = ProcessInfo.processInfo.environment
        let rootOverride = CustomWineSettings.root
        let wineOverride = CustomWineSettings.wine
        let wineserverOverride = CustomWineSettings.wineserver
        let filteredEnvironment = debugFilteredEnvironment(environment)
        let filteredParentEnvironment = debugFilteredEnvironment(customEnvironment)
        let fileOutput = debugFileOutput(for: executableURL)
        let quarantineOutput = debugQuarantineOutput(for: executableURL)
        let linkedLibraries = debugLinkedLibraries(for: executableURL)

        let rawMessage = """

        [BourbonWine Debug] Preparing Wine process launch
        Launch name: \(name)
        WHISKY_CUSTOM_WINE_ROOT detected: \(rootOverride != nil)
        WHISKY_CUSTOM_WINE_ROOT value: \(rootOverride ?? "<not set>")
        WHISKY_CUSTOM_WINE override used: \(wineOverride != nil)
        WHISKY_CUSTOM_WINE value: \(wineOverride ?? "<not set>")
        WHISKY_CUSTOM_WINESERVER override used: \(wineserverOverride != nil)
        WHISKY_CUSTOM_WINESERVER value: \(wineserverOverride ?? "<not set>")
        Selected Wine executable: \(executablePath)
        Resolved wineserver executable: \(wineserverBinary.path(percentEncoded: false))
        Process executable: \(executablePath)
        Process arguments: \(args)
        Process working directory: \(workingDirectory?.path(percentEncoded: false) ?? "<nil>")
        Executable exists: \(exists)
        Executable is directory: \(isDirectory.boolValue)
        Executable is executable: \(isExecutable)
        Executable POSIX permissions: \(permissionText)
        Bourbon process architecture: \(debugHostArchitecture); Rosetta installed: \(Rosetta2.isRosettaInstalled)
        file output: \(fileOutput)
        quarantine attribute: \(quarantineOutput)
        linked libraries / dylib inspection:
        \(linkedLibraries)
        Filtered child environment:
        \(filteredEnvironment)
        Filtered Bourbon app environment:
        \(filteredParentEnvironment)

        """
        let message = WineDiagnosticSanitizer.redact(rawMessage)
        Logger.wineKit.info("\(message, privacy: .public)")
        fileHandle?.write(line: message)
    }

    static func debugLogProcessLaunchError(
        _ error: Error,
        name: String,
        executableURL: URL,
        fileHandle: FileHandle?
    ) {
        let errorText = String(describing: error)
        let rosettaContext: String
        if error.localizedDescription.contains("Attachment of code signature supplement failed")
            || errorText.contains("Attachment of code signature supplement failed") {
            rosettaContext = """
            Rosetta/code-signature context: failure happened while calling Process.run, \
            before Bourbon received a running Wine process.
            """
        } else {
            rosettaContext = "Rosetta/code-signature context: " +
                "no matching Rosetta supplement error in Process.run error."
        }

        let rawMessage = """

        [BourbonWine Debug] Process launch error
        Launch name: \(name)
        Process executable: \(executableURL.path(percentEncoded: false))
        Error localizedDescription: \(error.localizedDescription)
        Error description: \(errorText)
        \(rosettaContext)

        """
        let message = WineDiagnosticSanitizer.redact(rawMessage)
        Logger.wineKit.error("\(message, privacy: .public)")
        fileHandle?.write(line: message)
    }

    static func debugFilteredEnvironment(_ environment: [String: String]) -> String {
        WineDiagnosticSanitizer.redactEnvironment(
            WineDiagnosticSanitizer.filteredRuntimeEnvironment(environment)
        )
    }

    static var debugHostArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    static func debugFileOutput(for url: URL) -> String {
        debugCommandOutput(
            executable: URL(fileURLWithPath: "/usr/bin/file"),
            arguments: [url.path(percentEncoded: false)]
        )
    }

    static func debugQuarantineOutput(for url: URL) -> String {
        debugCommandOutput(
            executable: URL(fileURLWithPath: "/usr/bin/xattr"),
            arguments: ["-p", "com.apple.quarantine", url.path(percentEncoded: false)],
            emptyResult: "<not quarantined>"
        )
    }

    static func debugLinkedLibraries(for url: URL) -> String {
        debugCommandOutput(
            executable: URL(fileURLWithPath: "/usr/bin/otool"),
            arguments: ["-L", url.path(percentEncoded: false)]
        )
    }

    static func debugCommandOutput(
        executable: URL,
        arguments: [String],
        emptyResult: String = "<no output>"
    ) -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let output, !output.isEmpty else { return emptyResult }
            return WineDiagnosticSanitizer.excerpt(from: output)
        } catch {
            return "diagnostic command failed: \(WineDiagnosticSanitizer.redact(error.localizedDescription))"
        }
    }
    static func runProgramArguments(for url: URL, args: [String]) -> [String] {
        let path = url.path(percentEncoded: false)
        switch url.pathExtension.lowercased() {
        case "exe":
            return [path] + args
        case "msi":
            return ["msiexec", "/i", path] + args
        default:
            return ["start", "/unix", path] + args
        }
    }

    static func generateRunProgramCommand(at url: URL, args: String) -> String {
        switch url.pathExtension.lowercased() {
        case "exe":
            return "\(wineBinary.esc) \(url.esc) \(args)"
        case "msi":
            return "\(wineBinary.esc) msiexec /i \(url.esc) \(args)"
        default:
            return "\(wineBinary.esc) start /unix \(url.esc) \(args)"
        }
    }

    struct ProgramLaunchDiagnostics {
        let isWindowsExecutable: Bool
        let peType: String
        let architecture: String
        let machine: String
        let subsystem: String
        let imageBase: UInt64?
        let sizeOfImage: UInt32?
        let relocationsStripped: Bool?

        static func inspect(url: URL) -> ProgramLaunchDiagnostics {
            guard url.pathExtension.lowercased() == "exe" else {
                return ProgramLaunchDiagnostics(
                    isWindowsExecutable: false,
                    peType: "not inspected",
                    architecture: "not inspected",
                    machine: "not inspected",
                    subsystem: "not inspected",
                    imageBase: nil,
                    sizeOfImage: nil,
                    relocationsStripped: nil
                )
            }

            do {
                let peFile = try PEFile(url: url)
                return ProgramLaunchDiagnostics(
                    isWindowsExecutable: true,
                    peType: peFile.optionalHeader?.magic.description ?? "unknown",
                    architecture: peFile.architecture.toString() ?? "unknown",
                    machine: String(format: "0x%04X", peFile.coffFileHeader.machine),
                    subsystem: subsystemDescription(peFile.optionalHeader?.subsystem),
                    imageBase: peFile.optionalHeader?.imageBase,
                    sizeOfImage: peFile.optionalHeader?.sizeOfImage,
                    relocationsStripped: peFile.coffFileHeader.characteristics & 0x0001 != 0
                )
            } catch {
                return ProgramLaunchDiagnostics(
                    isWindowsExecutable: true,
                    peType: "unknown",
                    architecture: "unknown",
                    machine: "unknown",
                    subsystem: "unknown",
                    imageBase: nil,
                    sizeOfImage: nil,
                    relocationsStripped: nil
                )
            }
        }

        var isWindowsGUI: Bool {
            subsystem.hasPrefix("Windows GUI")
        }

        var hasLowFixedImageBase: Bool {
            guard let imageBase, relocationsStripped == true else { return false }
            return imageBase < 0x6800_0000
        }

        var summary: String {
            let imageBase = imageBase.map { String(format: "0x%llX", $0) } ?? "unknown"
            let sizeOfImage = sizeOfImage.map { String(format: "0x%X", $0) } ?? "unknown"
            let relocations = relocationsStripped.map { $0 ? "stripped" : "present" } ?? "unknown"
            return "PE Type: \(peType), Architecture: \(architecture), Machine: \(machine), " +
                "Subsystem: \(subsystem), ImageBase: \(imageBase), SizeOfImage: \(sizeOfImage), " +
                "Relocations: \(relocations)"
        }

        private static func subsystemDescription(_ value: UInt16?) -> String {
            guard let value else { return "unknown" }
            switch value {
            case 2:
                return "Windows GUI (0x0002)"
            case 3:
                return "Windows console (0x0003)"
            default:
                return String(format: "0x%04X", value)
            }
        }
    }

    struct ProgramLaunchError: LocalizedError {
        let url: URL
        let diagnostics: ProgramLaunchDiagnostics
        let output: String

        var errorDescription: String? {
            var message = "BourbonWine could not launch \(url.lastPathComponent)."
            if !output.isEmpty {
                message += "\n\nWine output:\n\(output)"
            }
            return message
        }
    }

    /// Distinguishes a deliberate prefix shutdown from a genuine Wine launch failure.
    public struct ProgramLaunchIntentionalTermination: Error, Sendable {
        public let url: URL

        public init(url: URL) {
            self.url = url
        }
    }

    static func logProgramLaunchDiagnostics(
        url: URL, diagnostics: ProgramLaunchDiagnostics, fileHandle: FileHandle
    ) {
        #if DEBUG
        guard diagnostics.isWindowsExecutable else { return }
        Logger.wineKit.info(
            """
            Launching Windows executable: \(url.path(percentEncoded: false), privacy: .public)
            \(diagnostics.summary, privacy: .public)
            """
        )
        fileHandle.write(
            line: """
            Launch Diagnostics:
            File: \(url.path(percentEncoded: false))
            \(diagnostics.summary)

            """
        )
        #endif
    }

    static func logCompatibilityLaunchPlan(_ plan: CompatibilityLaunchPlan, fileHandle: FileHandle) {
        #if DEBUG
        let technologies = plan.analysis.technologies
            .map(\.rawValue)
            .sorted()
            .joined(separator: ", ")
        let rule = plan.ruleID ?? "normal-launch"
        let profiles = plan.appliedProfiles.isEmpty
            ? "none"
            : plan.appliedProfiles.joined(separator: ", ")
        let finalArguments = plan.arguments.isEmpty
            ? "none"
            : plan.arguments.joined(separator: " ")
        Logger.wineKit.info(
            """
            Compatibility launch plan:
            Rule: \(rule, privacy: .public)
            Technologies: \(technologies, privacy: .public)
            Applied launch profiles: \(profiles, privacy: .public)
            Target: \(plan.executableURL.path(percentEncoded: false), privacy: .public)
            Final arguments: \(finalArguments, privacy: .public)
            """
        )
        fileHandle.write(
            line: """
            Compatibility:
            Rule: \(rule)
            Technologies: \(technologies)
            Applied launch profiles: \(profiles)
            Target: \(plan.executableURL.path(percentEncoded: false))
            Final arguments: \(finalArguments)

            """
        )
        #endif
    }

    static func logFinalLaunchDiagnostics(
        for plan: CompatibilityLaunchPlan,
        originalURL: URL,
        fileHandle: FileHandle
    ) -> ProgramLaunchDiagnostics {
        let diagnostics = ProgramLaunchDiagnostics.inspect(url: plan.executableURL)
        #if DEBUG
        guard plan.executableURL != originalURL else { return diagnostics }
        logProgramLaunchDiagnostics(
            url: plan.executableURL,
            diagnostics: diagnostics,
            fileHandle: fileHandle
        )
        #endif
        return diagnostics
    }

    private static func outputMode(
        for plan: CompatibilityLaunchPlan,
        diagnostics: ProgramLaunchDiagnostics
    ) -> WineProcessOutputMode {
        // GUI programs still present their own windows with stdout/stderr piped.  Capturing
        // is essential for diagnosing a nonzero Wine exit; PE type must not discard it.
        _ = plan
        _ = diagnostics
        return .captured
    }

    private static func logProgramOutputMode(_ mode: WineProcessOutputMode, fileHandle: FileHandle) {
        #if DEBUG
        let description: String
        switch mode {
        case .captured:
            description = "captured stdout/stderr"
        }

        Logger.wineKit.info("Wine output mode: \(description, privacy: .public)")
        fileHandle.write(
            line: """
            Wine output mode:
            \(description)

            """
        )
        #endif
    }
}

public extension Wine {
    struct RuntimeDependency: Identifiable, Sendable {
        public let id: String
        public let libraryName: String
        public let displayName: String
        public let reason: String
        public let installHint: String
        public let required: Bool

        public var isInstalled: Bool {
            FileManager.default.fileExists(atPath: Wine.wineLibraryFolder.appending(path: libraryName).path)
        }
    }

    static let runtimeDependencies: [RuntimeDependency] = [
        RuntimeDependency(
            id: "freetype",
            libraryName: "libfreetype.6.dylib",
            displayName: "FreeType",
            reason: "Wine uses FreeType to render Windows fonts.",
            installHint: "Rebuild the Sikarugir archive with FreeType bundled, " +
                "or install FreeType locally for development with: brew install freetype",
            required: false
        ),
        RuntimeDependency(
            id: "gnutls",
            libraryName: "libgnutls.30.dylib",
            displayName: "GnuTLS",
            reason: "Wine uses GnuTLS for encrypted connections and certificate import/export.",
            installHint: "Rebuild the Sikarugir archive with GnuTLS bundled, " +
                "or install GnuTLS locally for development with: brew install gnutls",
            required: false
        )
    ]

    static func missingRuntimeDependencies(requiredOnly: Bool = true) -> [RuntimeDependency] {
        runtimeDependencies.filter { dependency in
            (!requiredOnly || dependency.required) && !dependency.isInstalled
        }
    }
}

enum WineInterfaceError: Error {
    case invalidResponce
}

enum RegistryType: String {
    case binary = "REG_BINARY"
    case dword = "REG_DWORD"
    case qword = "REG_QWORD"
    case string = "REG_SZ"
}

extension Wine {
    public static let logsFolder = FileManager.default.urls(
        for: .libraryDirectory, in: .userDomainMask
    )[0].appending(path: "Logs").appending(path: Bundle.whiskyBundleIdentifier)

    public static func makeFileHandle() throws -> FileHandle {
        try makeFileHandle(in: Self.logsFolder)
    }

    static func makeFileHandle(in logsFolder: URL) throws -> FileHandle {
        if !FileManager.default.fileExists(atPath: logsFolder.path) {
            try FileManager.default.createDirectory(at: logsFolder, withIntermediateDirectories: true)
        }

        let dateString = "\(Date.now.ISO8601Format())-\(UUID().uuidString)"
        let fileURL = logsFolder.appending(path: dateString).appendingPathExtension("log")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)
        return try FileHandle(forWritingTo: fileURL)
    }
}

extension Wine {
    private enum RegistryKey: String {
        case currentVersion = #"HKLM\Software\Microsoft\Windows NT\CurrentVersion"#
        case macDriver = #"HKCU\Software\Wine\Mac Driver"#
        case desktop = #"HKCU\Control Panel\Desktop"#
    }

    private static func addRegistryKey(
        bottle: Bottle, key: String, name: String, data: String, type: RegistryType
    ) async throws {
        try await runWine(
            ["reg", "add", key, "-v", name, "-t", type.rawValue, "-d", data, "-f"],
            bottle: bottle
        )
    }

    private static func queryRegistryKey(
        bottle: Bottle, key: String, name: String, type: RegistryType
    ) async throws -> String? {
        let output = try await runWine(["reg", "query", key, "-v", name], bottle: bottle)
        let lines = output.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)

        guard let line = lines.first(where: { $0.contains(type.rawValue) }) else { return nil }
        let array = line.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
        guard let value = array.last else { return nil }
        return String(value)
    }

    public static func changeBuildVersion(bottle: Bottle, version: Int) async throws {
        try await addRegistryKey(bottle: bottle, key: RegistryKey.currentVersion.rawValue,
                                name: "CurrentBuild", data: "\(version)", type: .string)
        try await addRegistryKey(bottle: bottle, key: RegistryKey.currentVersion.rawValue,
                                name: "CurrentBuildNumber", data: "\(version)", type: .string)
    }

    public static func winVersion(bottle: Bottle) async throws -> WinVersion {
        let output = try await Wine.runWine(["winecfg", "-v"], bottle: bottle)
        let lines = output.split(whereSeparator: \.isNewline)

        if let lastLine = lines.last {
            let winString = String(lastLine)

            if let version = WinVersion(rawValue: winString) {
                return version
            }
        }

        throw WineInterfaceError.invalidResponce
    }

    public static func buildVersion(bottle: Bottle) async throws -> String? {
        return try await Wine.queryRegistryKey(
            bottle: bottle, key: RegistryKey.currentVersion.rawValue,
            name: "CurrentBuild", type: .string
        )
    }

    public static func retinaMode(bottle: Bottle) async throws -> Bool {
        let values: Set<String> = ["y", "n"]
        guard let output = try await Wine.queryRegistryKey(
            bottle: bottle, key: RegistryKey.macDriver.rawValue, name: "RetinaMode", type: .string
        ), values.contains(output) else {
            try await changeRetinaMode(bottle: bottle, retinaMode: false)
            return false
        }
        return output == "y"
    }

    public static func changeRetinaMode(bottle: Bottle, retinaMode: Bool) async throws {
        try await Wine.addRegistryKey(
            bottle: bottle, key: RegistryKey.macDriver.rawValue, name: "RetinaMode", data: retinaMode ? "y" : "n",
            type: .string
        )
    }

    public static func dpiResolution(bottle: Bottle) async throws -> Int? {
        guard let output = try await Wine.queryRegistryKey(bottle: bottle, key: RegistryKey.desktop.rawValue,
                                                     name: "LogPixels", type: .dword
        ) else { return nil }

        let noPrefix = output.replacingOccurrences(of: "0x", with: "")
        let int = Int(noPrefix, radix: 16)
        guard let int = int else { return nil }
        return int
    }

    public static func changeDpiResolution(bottle: Bottle, dpi: Int) async throws {
        try await Wine.addRegistryKey(
            bottle: bottle, key: RegistryKey.desktop.rawValue, name: "LogPixels", data: String(dpi),
            type: .dword
        )
    }

    @discardableResult
    public static func control(bottle: Bottle) async throws -> String {
        return try await Wine.runWine(["control"], bottle: bottle)
    }

    @discardableResult
    public static func regedit(bottle: Bottle) async throws -> String {
        return try await Wine.runWine(["regedit"], bottle: bottle)
    }

    @discardableResult
    public static func cfg(bottle: Bottle) async throws -> String {
        return try await Wine.runWine(["winecfg"], bottle: bottle)
    }

    @discardableResult
    public static func changeWinVersion(
        bottle: Bottle,
        win: WinVersion,
        operation: BottleWineOperation? = nil
    ) async throws -> String {
        let executableURL = resolveWineExecutable()
        return try await runWineCommand(
            ["winecfg", "-v", win.rawValue],
            bottle: bottle,
            phase: "configuration",
            timeoutSeconds: operation == nil ? nil : 120,
            operation: operation,
            singleInvocation: operation != nil,
            executableURL: executableURL
        )
    }

    public static func settleBottleCreation(
        bottle: Bottle,
        operation: BottleWineOperation
    ) async throws {
        do {
            _ = try await runWineCommand(
                ["-w"],
                bottle: bottle,
                phase: "settlement",
                timeoutSeconds: 30,
                operation: operation,
                executableURL: wineserverBinary
            )
        } catch is WineCommandTimeoutError {
            try? await stopBottleProcesses(
                bottle: bottle,
                operation: operation,
                reason: "settlement_timeout"
            )
            throw BottleWineOperationError.wineSettlementTimeout
        }
    }

    /// Stops Wine activity only for this Bottle's WINEPREFIX, then waits for bounded settlement.
    public static func stopBottleProcesses(
        bottle: Bottle,
        operation: BottleWineOperation? = nil,
        reason: String
    ) async throws {
        operation?.cancel(reason: reason)
        BottleWineLifecycle.shared.beginCleanup(
            bottle: bottle,
            reason: reason,
            wineserver: wineserverBinary
        )
        let cleanup = Task.detached(priority: .userInitiated) {
            do {
                _ = try await runWineCommand(
                    ["-k"],
                    bottle: bottle,
                    phase: "prefix_cleanup",
                    timeoutSeconds: 10,
                    operation: operation,
                    executableURL: wineserverBinary
                )
                _ = try await runWineCommand(
                    ["-w"],
                    bottle: bottle,
                    phase: "prefix_cleanup_wait",
                    timeoutSeconds: 10,
                    operation: operation,
                    executableURL: wineserverBinary
                )
                BottleWineLifecycle.shared.finishCleanup(bottle: bottle, result: "prefix_terminated")
            } catch is WineCommandTimeoutError {
                BottleWineLifecycle.shared.finishCleanup(bottle: bottle, result: "timeout")
                throw BottleWineOperationError.wineCancellationTimeout
            } catch {
                BottleWineLifecycle.shared.finishCleanup(bottle: bottle, result: "failed")
                throw error
            }
        }
        try await cleanup.value
    }
}

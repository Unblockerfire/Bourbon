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

import Foundation
import os.log

// swiftlint:disable:next type_body_length
public class Wine {
    private enum WineProcessOutputMode {
        case captured
        case normalGUI
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

            [Whisky Wine Debug] App startup custom Wine configuration
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
        customWineRunner?.wine ?? WhiskyWineInstaller.binFolder.appending(path: "wine64")
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
        // swiftlint:disable:next todo
        // TODO: Remove this temporary startup diagnostic after the custom Wine/Rosetta issue is resolved.
        Logger.wineKit.info("\(CustomWineSettings.startupDebugMessage, privacy: .public)")
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
            case .normalGUI:
                return try process.runUncaptured(name: processName, fileHandle: fileHandle)
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
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment, executableURL: wineBinary,
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

        for await result in stream {
            switch result {
            case .started:
                break
            case .message(let message), .error(let message):
                output.append(message)
            case .terminated(let process):
                terminationStatus = process.terminationStatus
            }
        }

        guard terminationStatus == 0 else {
            Logger.wineKit.warning(
                """
                Failed to launch \(url.lastPathComponent, privacy: .public).
                \(diagnostics.summary, privacy: .public)
                """
            )
            throw ProgramLaunchError(
                url: url,
                diagnostics: launchDiagnostics,
                output: output.joined().trimmingCharacters(in: .whitespacesAndNewlines)
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
        var result: [String] = []
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicaitonInfo()
        var environment = constructWineRuntimeEnvironment(environment)

        if let bottle = bottle {
            fileHandle.writeInfo(for: bottle)
            environment = constructWineEnvironment(for: bottle, environment: environment)
        }

        for await output in try runWineProcess(args: args, environment: environment, fileHandle: fileHandle) {
            switch output {
            case .started, .terminated:
                break
            case .message(let message), .error(let message):
                result.append(message)
            }
        }

        return result.joined()
    }

    public static func wineVersion() async throws -> String {
        var output = try await runWine(["--version"], bottle: nil)
        output.replace("wine-", with: "")

        // Deal with WineCX version names
        if let index = output.firstIndex(where: { $0.isWhitespace }) {
            return String(output.prefix(upTo: index))
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    public static func runBatchFile(url: URL, bottle: Bottle) async throws -> String {
        return try await runWine(["cmd", "/c", url.path(percentEncoded: false)], bottle: bottle)
    }

    public static func killBottle(bottle: Bottle) throws {
        Task.detached(priority: .userInitiated) {
            try await runWineserver(["-k"], bottle: bottle)
        }
    }

    public static func killProgram(program: Program, bottle: Bottle) throws {
        let executableName = program.url.lastPathComponent
        Task.detached(priority: .userInitiated) {
            try await runWine(["taskkill", "/F", "/IM", executableName], bottle: bottle)
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

private extension Wine {
    // swiftlint:disable:next todo
    // TODO: Remove this temporary launch diagnostics block after the custom Wine/Rosetta issue is resolved.
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
        let customEnvironment = ProcessInfo.processInfo.environment
        let rootOverride = CustomWineSettings.root
        let wineOverride = CustomWineSettings.wine
        let wineserverOverride = CustomWineSettings.wineserver
        let filteredEnvironment = debugFilteredEnvironment(environment)
        let filteredParentEnvironment = debugFilteredEnvironment(customEnvironment)
        let fileOutput = debugFileOutput(for: executableURL)

        let message = """

        [Whisky Wine Debug] Preparing Wine process launch
        Launch name: \(name)
        WHISKY_CUSTOM_WINE_ROOT detected: \(rootOverride != nil)
        WHISKY_CUSTOM_WINE_ROOT value: \(rootOverride ?? "<not set>")
        WHISKY_CUSTOM_WINE override used: \(wineOverride != nil)
        WHISKY_CUSTOM_WINE value: \(wineOverride ?? "<not set>")
        WHISKY_CUSTOM_WINESERVER override used: \(wineserverOverride != nil)
        WHISKY_CUSTOM_WINESERVER value: \(wineserverOverride ?? "<not set>")
        Resolved Wine executable: \(wineBinary.path(percentEncoded: false))
        Resolved wineserver executable: \(wineserverBinary.path(percentEncoded: false))
        Process executable: \(executablePath)
        Process arguments: \(args)
        Process working directory: \(workingDirectory?.path(percentEncoded: false) ?? "<nil>")
        Executable exists: \(exists)
        Executable is directory: \(isDirectory.boolValue)
        Executable is executable: \(isExecutable)
        file output: \(fileOutput)
        Filtered child environment:
        \(filteredEnvironment)
        Filtered Whisky app environment:
        \(filteredParentEnvironment)

        """
        Logger.wineKit.info("\(message, privacy: .public)")
        fileHandle?.write(line: message)
    }

    // swiftlint:disable:next todo
    // TODO: Remove this temporary launch diagnostics block after the custom Wine/Rosetta issue is resolved.
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
            before Whisky received a running Wine process.
            """
        } else {
            rosettaContext = "Rosetta/code-signature context: " +
                "no matching Rosetta supplement error in Process.run error."
        }

        let message = """

        [Whisky Wine Debug] Process launch error
        Launch name: \(name)
        Process executable: \(executableURL.path(percentEncoded: false))
        Error localizedDescription: \(error.localizedDescription)
        Error description: \(errorText)
        \(rosettaContext)

        """
        Logger.wineKit.error("\(message, privacy: .public)")
        fileHandle?.write(line: message)
    }

    static func debugFilteredEnvironment(_ environment: [String: String]) -> String {
        let prefixes = ["WINE", "DYLD", "PATH", "WHISKY_", "ROSETTA"]
        let values = environment
            .filter { key, _ in prefixes.contains(where: { key.hasPrefix($0) }) }
            .sorted { $0.key < $1.key }

        guard !values.isEmpty else { return "<none>" }
        return values
            .map { key, value in "\(key)=\(value)" }
            .joined(separator: "\n")
    }

    static func debugFileOutput(for url: URL) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/file")
        process.arguments = [url.path(percentEncoded: false)]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return output ?? "<unreadable file output>"
        } catch {
            return "file command failed: \(error.localizedDescription)"
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
            var message = "Wine could not launch \(url.lastPathComponent)."
            if diagnostics.peType == "PE32" || diagnostics.architecture == "32-bit" {
                message += " This appears to be a 32-bit Windows app. " +
                    "32-bit Windows apps may not be supported by this imported Sikarugir Wine runtime."
            } else if diagnostics.hasLowFixedImageBase {
                message += " This 64-bit Windows app has a fixed low image base and no relocation data. " +
                    "The imported Sikarugir Wine runtime could not reserve the low memory range it needs."
            }
            if !output.isEmpty {
                message += "\n\nWine output:\n\(output)"
            }
            return message
        }
    }

    static func logProgramLaunchDiagnostics(
        url: URL, diagnostics: ProgramLaunchDiagnostics, fileHandle: FileHandle
    ) {
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
    }

    static func logCompatibilityLaunchPlan(_ plan: CompatibilityLaunchPlan, fileHandle: FileHandle) {
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
    }

    static func logFinalLaunchDiagnostics(
        for plan: CompatibilityLaunchPlan,
        originalURL: URL,
        fileHandle: FileHandle
    ) -> ProgramLaunchDiagnostics {
        let diagnostics = ProgramLaunchDiagnostics.inspect(url: plan.executableURL)
        guard plan.executableURL != originalURL else { return diagnostics }
        logProgramLaunchDiagnostics(
            url: plan.executableURL,
            diagnostics: diagnostics,
            fileHandle: fileHandle
        )
        return diagnostics
    }

    private static func outputMode(
        for plan: CompatibilityLaunchPlan,
        diagnostics: ProgramLaunchDiagnostics
    ) -> WineProcessOutputMode {
        if diagnostics.isWindowsGUI || plan.analysis.technologies.contains(.electron) {
            return .normalGUI
        }
        return .captured
    }

    private static func logProgramOutputMode(_ mode: WineProcessOutputMode, fileHandle: FileHandle) {
        let description: String
        switch mode {
        case .captured:
            description = "captured stdout/stderr"
        case .normalGUI:
            description = "normal GUI launch; stdout/stderr are not piped into Swift"
        }

        Logger.wineKit.info("Wine output mode: \(description, privacy: .public)")
        fileHandle.write(
            line: """
            Wine output mode:
            \(description)

            """
        )
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
        if !FileManager.default.fileExists(atPath: Self.logsFolder.path) {
            try FileManager.default.createDirectory(at: Self.logsFolder, withIntermediateDirectories: true)
        }

        let dateString = Date.now.ISO8601Format()
        let fileURL = Self.logsFolder.appending(path: dateString).appendingPathExtension("log")
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
    public static func changeWinVersion(bottle: Bottle, win: WinVersion) async throws -> String {
        return try await Wine.runWine(["winecfg", "-v", win.rawValue], bottle: bottle)
    }
}

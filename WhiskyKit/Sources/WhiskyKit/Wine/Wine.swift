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

public class Wine {
    /// URL to the installed `DXVK` folder
    private static let dxvkFolder: URL = WhiskyWineInstaller.libraryFolder.appending(path: "DXVK")
    /// URL to the installed Wine `lib` directory.
    private static let wineLibraryFolder: URL = WhiskyWineInstaller.libraryFolder
        .appending(path: "Wine")
        .appending(path: "lib")
    /// Path to the `wine64` binary
    public static let wineBinary: URL = WhiskyWineInstaller.binFolder.appending(path: "wine64")
    /// Parth to the `wineserver` binary
    private static let wineserverBinary: URL = WhiskyWineInstaller.binFolder.appending(path: "wineserver")

    /// Run a process on a executable file given by the `executableURL`
    private static func runProcess(
        name: String? = nil, args: [String], environment: [String: String], executableURL: URL, directory: URL? = nil,
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = args
        process.currentDirectoryURL = directory ?? executableURL.deletingLastPathComponent()
        process.environment = environment
        process.qualityOfService = .userInitiated

        return try process.runStream(
            name: name ?? args.joined(separator: " "), fileHandle: fileHandle
        )
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    private static func runWineProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:],
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment, executableURL: wineBinary,
            fileHandle: fileHandle
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

    /// Execute a program with Wine, using direct execution for Windows installer binaries.
    public static func runProgram(
        at url: URL, args: [String] = [], bottle: Bottle, environment: [String: String] = [:]
    ) async throws {
        if bottle.settings.dxvk {
            try enableDXVK(bottle: bottle)
        }

        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicaitonInfo()
        fileHandle.writeInfo(for: bottle)

        let diagnostics = ProgramLaunchDiagnostics.inspect(url: url)
        logProgramLaunchDiagnostics(url: url, diagnostics: diagnostics, fileHandle: fileHandle)

        var output: [String] = []
        var terminationStatus: Int32 = 0

        let stream = try runWineProcess(
            name: url.lastPathComponent,
            args: runProgramArguments(for: url, args: args),
            environment: constructWineEnvironment(for: bottle, environment: environment),
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
                diagnostics: diagnostics,
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
        var cmd = """
        export PATH=\"\(WhiskyWineInstaller.binFolder.path):$PATH\"
        export DYLD_LIBRARY_PATH=\"\(wineLibraryFolder.path):${DYLD_LIBRARY_PATH:-}\"
        export DYLD_FALLBACK_LIBRARY_PATH=\"\(wineLibraryFolder.path):${DYLD_FALLBACK_LIBRARY_PATH:-}\"
        export WINE=\"wine64\"
        alias wine=\"wine64\"
        alias winecfg=\"wine64 winecfg\"
        alias msiexec=\"wine64 msiexec\"
        alias regedit=\"wine64 regedit\"
        alias regsvr32=\"wine64 regsvr32\"
        alias wineboot=\"wine64 wineboot\"
        alias wineconsole=\"wine64 wineconsole\"
        alias winedbg=\"wine64 winedbg\"
        alias winefile=\"wine64 winefile\"
        alias winepath=\"wine64 winepath\"
        """

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
                WhiskyWineInstaller.binFolder.path,
                ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            ].joined(separator: ":"),
            "DYLD_LIBRARY_PATH": wineLibraryFolder.path,
            "DYLD_FALLBACK_LIBRARY_PATH": wineLibraryFolder.path
        ]
        guard !environment.isEmpty else { return result }
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
    }
}

private extension Wine {
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

        static func inspect(url: URL) -> ProgramLaunchDiagnostics {
            guard url.pathExtension.lowercased() == "exe" else {
                return ProgramLaunchDiagnostics(
                    isWindowsExecutable: false,
                    peType: "not inspected",
                    architecture: "not inspected",
                    machine: "not inspected"
                )
            }

            do {
                let peFile = try PEFile(url: url)
                return ProgramLaunchDiagnostics(
                    isWindowsExecutable: true,
                    peType: peFile.optionalHeader?.magic.description ?? "unknown",
                    architecture: peFile.architecture.toString() ?? "unknown",
                    machine: String(format: "0x%04X", peFile.coffFileHeader.machine)
                )
            } catch {
                return ProgramLaunchDiagnostics(
                    isWindowsExecutable: true,
                    peType: "unknown",
                    architecture: "unknown",
                    machine: "unknown"
                )
            }
        }

        var summary: String {
            "PE Type: \(peType), Architecture: \(architecture), Machine: \(machine)"
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

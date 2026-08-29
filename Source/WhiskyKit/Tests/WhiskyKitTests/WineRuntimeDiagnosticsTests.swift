import XCTest
@testable import WhiskyKit

final class WineRuntimeDiagnosticsTests: XCTestCase {
    func testRedactsSensitiveProcessOutput() {
        let input = "password=hunter2 token: abcdefghijk user@example.com BRBN-1234567890ABCDEF"
        let output = WineDiagnosticSanitizer.redact(input)

        XCTAssertFalse(output.contains("hunter2"))
        XCTAssertFalse(output.contains("abcdefghijk"))
        XCTAssertFalse(output.contains("user@example.com"))
        XCTAssertFalse(output.contains("BRBN-1234567890ABCDEF"))
    }

    func testExcerptKeepsFailureAtEnd() {
        let output = WineDiagnosticSanitizer.excerpt(from: String(repeating: "a", count: 100) + "fatal", limit: 12)

        XCTAssertTrue(output.hasSuffix("fatal"))
        XCTAssertTrue(output.contains("truncated"))
    }

    func testRedactsSensitiveEnvironmentValuesByKey() {
        let output = WineDiagnosticSanitizer.redactEnvironment([
            "PATH": "/usr/bin:/bin",
            "SERVICE_CREDENTIAL": "do-not-log-this"
        ])

        XCTAssertTrue(output.contains("PATH=/usr/bin:/bin"))
        XCTAssertTrue(output.contains("SERVICE_CREDENTIAL=[redacted]"))
        XCTAssertFalse(output.contains("do-not-log-this"))
    }

    func testFiltersEnvironmentToRuntimeDiagnosticsAllowlist() {
        let output = WineDiagnosticSanitizer.filteredRuntimeEnvironment([
            "PATH": "/usr/bin:/bin",
            "WINEPREFIX": "/tmp/bottle",
            "DYLD_LIBRARY_PATH": "/runtime/lib",
            "UNRELATED_PRIVATE_VALUE": "do-not-log-this"
        ])

        XCTAssertEqual(output["PATH"], "/usr/bin:/bin")
        XCTAssertEqual(output["WINEPREFIX"], "/tmp/bottle")
        XCTAssertEqual(output["DYLD_LIBRARY_PATH"], "/runtime/lib")
        XCTAssertNil(output["UNRELATED_PRIVATE_VALUE"])
    }

    func testAcceptsWineVersionOutput() {
        XCTAssertTrue(WineDiagnosticSanitizer.isValidVersionOutput("wine-10.0 (Staging)\n"))
        XCTAssertTrue(WineDiagnosticSanitizer.isValidVersionOutput("wine64-9.22\n"))
        XCTAssertFalse(WineDiagnosticSanitizer.isValidVersionOutput("unexpected output\n"))
    }

    func testClassifiesRosettaFailure() {
        let error = WineDiagnosticSanitizer.classifiedFailure(
            details: "Bad CPU type in executable; Rosetta 2 is not available",
            executablePath: "/runtime/wine64",
            status: 1
        )

        guard case .rosettaUnavailable = error else {
            return XCTFail("Expected a Rosetta classification")
        }
    }

    func testClassifiesRuntimeLibraryFailure() {
        let error = WineDiagnosticSanitizer.classifiedFailure(
            details: "dyld: Library not loaded: @rpath/libwine.dylib",
            executablePath: "/runtime/wine64",
            status: 1
        )

        guard case .runtimeLibraryFailure = error else {
            return XCTFail("Expected a runtime library classification")
        }
    }

    func testPreservesUnknownNonzeroStatus() {
        let error = WineDiagnosticSanitizer.classifiedFailure(
            details: "wineboot failed",
            executablePath: "/runtime/wine64",
            status: 17
        )

        guard case .processNonzero(_, let status, let details) = error else {
            return XCTFail("Expected a nonzero process classification")
        }
        XCTAssertEqual(status, 17)
        XCTAssertTrue(details.contains("wineboot failed"))
    }

    func testUnifiedDescriptionPreservesClassifiedPreflightFailure() {
        let error = WineRuntimePreflightError.processNonzero(
            path: "/Applications/Bourbon.app/Contents/Resources/Libraries/Wine/bin/wine",
            status: 1,
            details: "wine failed to initialize"
        )

        XCTAssertEqual(
            error.unifiedLogDescription,
            "wine_runtime_preflight_process_nonzero " +
                "executable=Libraries/Wine/bin/wine arguments=--version " +
                "exit_status=1 details=wine failed to initialize"
        )
    }

    func testEveryPreflightClassificationHasStableSafeUnifiedDescription() {
        let path = "/Users/private-user/Libraries/Wine/bin/wine"
        let errors: [(WineRuntimePreflightError, String)] = [
            (.executableMissing(path: path), "executable_missing"),
            (.cannotExecute(path: path, details: "permission denied"), "cannot_execute"),
            (.rosettaUnavailable(path: path, details: "bad CPU type"), "rosetta_unavailable"),
            (
                .runtimeLibraryFailure(path: path, details: "dyld: libwine.dylib missing"),
                "runtime_library_failure"
            ),
            (.processNonzero(path: path, status: 1, details: "failed"), "process_nonzero"),
            (.invalidWineOutput(path: path, details: "unexpected"), "invalid_wine_output")
        ]

        for (error, code) in errors {
            let description = error.unifiedLogDescription
            XCTAssertTrue(description.hasPrefix("wine_runtime_preflight_\(code)"))
            XCTAssertTrue(description.contains("executable=Libraries/Wine/bin/wine"))
            XCTAssertTrue(description.contains("arguments=--version"))
            XCTAssertFalse(description.contains("private-user"))
            XCTAssertFalse(description.contains("\n"))
        }
    }

    func testUserFacingDescriptionContainsActionablePreflightDetails() {
        let error = WineRuntimePreflightError.runtimeLibraryFailure(
            path: "/Applications/Bourbon.app/Contents/Resources/Libraries/Wine/bin/wine",
            details: "dyld: Library not loaded: libwine.dylib"
        )

        XCTAssertTrue(error.userFacingDiagnosticMessage.contains("runtime_library_failure"))
        XCTAssertTrue(error.userFacingDiagnosticMessage.contains("Libraries/Wine/bin/wine"))
        XCTAssertTrue(error.userFacingDiagnosticMessage.contains("Arguments: --version"))
        XCTAssertTrue(error.userFacingDiagnosticMessage.contains("libwine.dylib"))
    }

    func testDiagnosticDescriptionsRedactHomePathAndSecrets() {
        let error = WineRuntimePreflightError.cannotExecute(
            path: "/Users/affected-user/Private/Wine/bin/wine",
            details: "token=super-secret /Users/affected-user/private.log"
        )
        let combined = error.unifiedLogDescription + error.userFacingDiagnosticMessage

        XCTAssertFalse(combined.contains("affected-user"))
        XCTAssertFalse(combined.contains("super-secret"))
        XCTAssertTrue(combined.contains("token=[redacted]"))
    }

    func testMissingExecutableFailureCreatesCommandLog() throws {
        let logsFolder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: logsFolder) }
        let executable = logsFolder.appending(path: "Libraries/Wine/bin/wine")
        let error = WineRuntimePreflightError.executableMissing(path: executable.path)

        Wine.recordPreflightFailure(error, executableURL: executable, logsFolder: logsFolder)

        let log = try newestLog(in: logsFolder)
        XCTAssertTrue(log.contains("Classification: executable_missing"))
        XCTAssertTrue(log.contains("Process arguments: [\"--version\"]"))
        XCTAssertTrue(log.contains("Executable exists: false"))
    }

    func testNonExecutableFailureCreatesCommandLog() throws {
        let logsFolder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: logsFolder) }
        let executable = logsFolder.appending(path: "wine")
        try FileManager.default.createDirectory(at: logsFolder, withIntermediateDirectories: true)
        try Data().write(to: executable)
        let error = WineRuntimePreflightError.cannotExecute(
            path: executable.path,
            details: "The file exists but does not have executable permission."
        )

        Wine.recordPreflightFailure(error, executableURL: executable, logsFolder: logsFolder)

        let log = try newestLog(in: logsFolder)
        XCTAssertTrue(log.contains("Classification: cannot_execute"))
        XCTAssertTrue(log.contains("Executable exists: true"))
        XCTAssertTrue(log.contains("Executable is executable: false"))
    }

    private func newestLog(in folder: URL) throws -> String {
        let logs = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "log" }
        let log = try XCTUnwrap(logs.max { $0.lastPathComponent < $1.lastPathComponent })
        return try String(contentsOf: log, encoding: .utf8)
    }
}

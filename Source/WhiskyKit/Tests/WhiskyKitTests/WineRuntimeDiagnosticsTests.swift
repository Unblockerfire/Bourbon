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

        guard case .processNonzero(let status, let details) = error else {
            return XCTFail("Expected a nonzero process classification")
        }
        XCTAssertEqual(status, 17)
        XCTAssertTrue(details.contains("wineboot failed"))
    }
}

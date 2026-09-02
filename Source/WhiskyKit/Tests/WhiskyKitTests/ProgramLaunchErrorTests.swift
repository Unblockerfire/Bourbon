import XCTest
@testable import WhiskyKit

final class ProgramLaunchErrorTests: XCTestCase {
    func testPE32FailureDoesNotClaimUnsupportedArchitectureWithoutEvidence() {
        let error = Wine.ProgramLaunchError(
            url: URL(fileURLWithPath: "/tmp/Steam.exe"),
            diagnostics: diagnostics(),
            output: "loader failed"
        )

        let message = error.localizedDescription
        XCTAssertTrue(message.contains("BourbonWine could not launch Steam.exe."))
        XCTAssertTrue(message.contains("loader failed"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("32-bit Windows app"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("Sikarugir"))
    }

    func testSteamWebViewDetectionDoesNotInjectCompatibilityFlags() {
        let profile = ChromiumWebViewLaunchProfile()
        let executable = URL(fileURLWithPath: "/tmp/Steam.exe")
        let analysis = InstallerAnalysis(
            url: executable,
            technologies: [.steamWebView, .portableExecutable],
            architecture: .x32,
            peType: "PE32",
            payloadHints: [],
            cacheKey: "steam"
        )
        let target = PreparedCompatibilityTarget(
            executableURL: executable,
            workingDirectory: executable.deletingLastPathComponent()
        )

        XCTAssertFalse(profile.applies(to: analysis, target: target))
    }

    private func diagnostics() -> Wine.ProgramLaunchDiagnostics {
        Wine.ProgramLaunchDiagnostics(
            isWindowsExecutable: true,
            peType: "PE32",
            architecture: "32-bit",
            machine: "0x014C",
            subsystem: "Windows GUI (0x0002)",
            imageBase: nil,
            sizeOfImage: nil,
            relocationsStripped: nil
        )
    }
}

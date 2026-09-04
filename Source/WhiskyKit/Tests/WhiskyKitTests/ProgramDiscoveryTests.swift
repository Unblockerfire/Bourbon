import XCTest
@testable import WhiskyKit

final class ProgramDiscoveryTests: XCTestCase {
    func testUserFacingLaunchersRemainDiscoverable() {
        XCTAssertTrue(ProgramDiscovery.isUserFacingExecutable(at: executable("Steam.exe")))
        XCTAssertTrue(ProgramDiscovery.isUserFacingExecutable(at: executable("My Game Launcher.exe")))
    }

    func testInfrastructureAndHelperExecutablesAreExcluded() {
        [
            "Fossilize Replay.exe",
            "Fossilize Replay64.exe",
            "GLdriverquery.exe",
            "Crashpad Handler.exe",
            "unins000.exe",
            "vc_redist.x64.exe",
            "WineCfg.exe"
        ].forEach { name in
            XCTAssertFalse(ProgramDiscovery.isUserFacingExecutable(at: executable(name)), name)
        }
    }

    private func executable(_ name: String) -> URL {
        URL(fileURLWithPath: "/prefix/drive_c/Program Files/Test/\(name)")
    }
}

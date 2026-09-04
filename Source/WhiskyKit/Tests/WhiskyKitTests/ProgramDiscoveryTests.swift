import XCTest
@testable import WhiskyKit

final class ProgramDiscoveryTests: XCTestCase {
    func testUserFacingLaunchersRemainDiscoverable() {
        XCTAssertTrue(ProgramDiscovery.isUserFacingExecutable(at: executable("Steam.exe")))
        XCTAssertTrue(ProgramDiscovery.isUserFacingExecutable(at: executable("My Game Launcher.exe")))
    }

    func testNotepadPlusPlusDoesNotCollapseIntoWineBuiltInNotepad() {
        let notepadPlusPlus = executable("Notepad++/notepad++.exe")

        XCTAssertTrue(ProgramDiscovery.isUserFacingExecutable(at: notepadPlusPlus))
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

    func testNewlyInstalledExecutablesReturnsOnlyNewEligiblePrograms() {
        let existingSteam = executable("Steam/steam.exe")
        let notepadPlusPlus = executable("Notepad++/notepad++.exe")
        let steamAlias = URL(fileURLWithPath: "/PREFIX/drive_c/Program Files/Test/Steam/STEAM.EXE")

        XCTAssertEqual(
            ProgramDiscovery.canonicalExecutablePath(for: existingSteam),
            ProgramDiscovery.canonicalExecutablePath(for: steamAlias)
        )

        XCTAssertEqual(
            ProgramDiscovery.newlyInstalledExecutables(
                before: [existingSteam],
                after: [steamAlias, notepadPlusPlus]
            ),
            [notepadPlusPlus]
        )
    }

    func testPreferredExecutableSelectsProductLauncherAmongMultipleNewApps() {
        let updater = executable("Notepad++/updater/GUP.exe")
        let notepadPlusPlus = executable("Notepad++/notepad++.exe")
        let documentation = executable("Notepad++/docs/readme.exe")

        XCTAssertEqual(
            ProgramDiscovery.preferredExecutable(from: [updater, documentation, notepadPlusPlus]),
            notepadPlusPlus
        )
    }

    func testNoNewApplicationProducesNoPostInstallerHandoffCandidate() {
        let steam = executable("Steam/steam.exe")
        let newPrograms = ProgramDiscovery.newlyInstalledExecutables(
            before: [steam],
            after: [steam]
        )

        XCTAssertTrue(newPrograms.isEmpty)
        XCTAssertNil(ProgramDiscovery.preferredExecutable(from: newPrograms))
    }

    private func executable(_ name: String) -> URL {
        URL(fileURLWithPath: "/prefix/drive_c/Program Files/Test/\(name)")
    }
}

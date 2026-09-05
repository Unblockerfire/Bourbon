import XCTest
@testable import WhiskyKit

final class ProgramLaunchConfigurationTests: XCTestCase {
    func testTerminalAndNativeConfigurationShareCoreWineValues() throws {
        let fixture = try LaunchFixture()
        defer { fixture.remove() }
        let target = fixture.bottle.url
            .appending(path: "drive_c/Program Files/Notepad++/notepad++.exe")
        let userArguments = ["--open", "C:\\Users\\Public\\notes file.txt"]
        let overrides = ["LC_ALL": "en_US.UTF-8"]

        let configuration = Wine.programProcessConfiguration(
            at: target,
            args: userArguments,
            bottle: fixture.bottle,
            environment: overrides
        )
        let terminalCommand = Wine.generateRunCommand(
            at: target,
            bottle: fixture.bottle,
            args: #"--open "C:\Users\Public\notes file.txt""#,
            environment: overrides
        )

        XCTAssertEqual(configuration.wineExecutable, Wine.resolveWineExecutable())
        XCTAssertEqual(configuration.targetExecutable, target)
        XCTAssertEqual(configuration.arguments, [target.path] + userArguments)
        XCTAssertEqual(configuration.workingDirectory, target.deletingLastPathComponent())
        XCTAssertEqual(configuration.environment["WINEPREFIX"], fixture.bottle.url.path)
        XCTAssertEqual(configuration.environment["DYLD_LIBRARY_PATH"], expectedWineLibraryPath)
        XCTAssertEqual(configuration.environment["DYLD_FALLBACK_LIBRARY_PATH"], expectedWineLibraryPath)
        XCTAssertEqual(configuration.environment["WINEMSYNC"], "1")
        XCTAssertEqual(configuration.environment["WINEESYNC"], "1")
        XCTAssertEqual(configuration.environment["LC_ALL"], "en_US.UTF-8")

        XCTAssertTrue(terminalCommand.contains(configuration.wineExecutable.path.esc))
        XCTAssertTrue(terminalCommand.contains("WINEPREFIX=\(fixture.bottle.url.path.esc)"))
        XCTAssertTrue(terminalCommand.contains("DYLD_LIBRARY_PATH=\(expectedWineLibraryPath.esc)"))
        XCTAssertTrue(terminalCommand.contains("DYLD_FALLBACK_LIBRARY_PATH=\(expectedWineLibraryPath.esc)"))
        XCTAssertTrue(terminalCommand.hasPrefix("cd \(configuration.workingDirectory.path.esc) && "))
    }

    func testQuotedUserArgumentsArePreservedForNativeLaunch() {
        XCTAssertEqual(
            Wine.parseProgramArguments(#"--name "Bourbon Test" --path 'C:\Program Files\App' --empty """#),
            ["--name", "Bourbon Test", "--path", "C:\\Program Files\\App", "--empty", ""]
        )
    }

    func testExplicitWorkingDirectoryIsPreserved() throws {
        let fixture = try LaunchFixture()
        defer { fixture.remove() }
        let target = fixture.bottle.url.appending(path: "drive_c/app.exe")
        let directory = fixture.bottle.url.appending(path: "drive_c")

        let configuration = Wine.programProcessConfiguration(
            at: target,
            args: [],
            bottle: fixture.bottle,
            workingDirectory: directory
        )

        XCTAssertEqual(configuration.workingDirectory, directory)
    }

    func testTerminalEquivalentGUIUsesUncapturedProcessMode() {
        let diagnostics = Wine.ProgramLaunchDiagnostics(
            isWindowsExecutable: true,
            peType: "PE32+",
            architecture: "x86_64",
            machine: "0x8664",
            subsystem: "Windows GUI (0x0002)",
            imageBase: nil,
            sizeOfImage: nil,
            relocationsStripped: nil
        )

        XCTAssertFalse(Wine.shouldCaptureProgramOutput(
            launchMode: .terminalEquivalentGUI,
            diagnostics: diagnostics
        ))
        XCTAssertTrue(Wine.shouldCaptureProgramOutput(
            launchMode: .captured,
            diagnostics: diagnostics
        ))
    }

    private var expectedWineLibraryPath: String {
        WhiskyWineInstaller.libraryFolder.appending(path: "Wine/lib").path
    }
}

private final class LaunchFixture {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "BourbonProgramLaunchTests-\(UUID().uuidString)")
    let bottle: Bottle

    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        bottle = Bottle(bottleUrl: root.appending(path: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

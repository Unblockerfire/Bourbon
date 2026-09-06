import XCTest
@testable import WhiskyKit

final class ApplicationDiscoveryTests: XCTestCase {
    func testCanonicalIdentityTreatsWindowsPathCasingAsTheSameExecutable() {
        let lower = URL(fileURLWithPath: "/PREFIX/drive_c/Program Files (x86)/Steam/steam.exe")
        let upper = URL(fileURLWithPath: "/prefix/drive_c/Program Files (x86)/Steam/STEAM.EXE")
        XCTAssertEqual(
            ApplicationDiscovery.canonicalIdentifier(for: lower),
            ApplicationDiscovery.canonicalIdentifier(for: upper)
        )
    }

    func testFiltersUpdaterAndRuntimeHelpersButKeepsMainApplication() {
        let names = ["notepad++.exe", "GUP.exe", "gldriverquery64.exe", "Fossilize Replay.exe", "unins000.exe"]
        let urls = names.map { URL(fileURLWithPath: "/prefix/drive_c/Program Files/App/\($0)") }
        let result = ApplicationDiscovery.deduplicatedEligibleURLs(urls)
        XCTAssertEqual(result.urls.map(\.lastPathComponent), ["notepad++.exe"])
        XCTAssertEqual(result.report.rawCandidateCount, 5)
        XCTAssertEqual(result.report.acceptedApplicationCount, 1)
        XCTAssertEqual(result.report.rejectedHelperCount, 4)
    }

    func testDeduplicatesMainApplicationsByCanonicalPath() {
        let result = ApplicationDiscovery.deduplicatedEligibleURLs([
            URL(fileURLWithPath: "/PREFIX/drive_c/Program Files/Steam/steam.exe"),
            URL(fileURLWithPath: "/prefix/drive_c/Program Files/Steam/STEAM.EXE")
        ])
        XCTAssertEqual(result.urls.count, 1)
    }
}

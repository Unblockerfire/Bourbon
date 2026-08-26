import XCTest
@testable import WhiskyKit
import SemanticVersion

final class WhiskyWineVersionInfoTests: XCTestCase {
    func testInstalledRuntimeVersionIsWrittenFromRuntimeMetadata() throws {
        let data = try WhiskyWineInstaller.installedVersionMarkerData(runtimeVersion: "1.0.1")
        let versionInfo = try PropertyListDecoder().decode(WhiskyWineVersionInfo.self, from: try XCTUnwrap(data))

        XCTAssertEqual(versionInfo.version, SemanticVersion(1, 0, 1))
    }

    func testMissingRuntimeMetadataDoesNotInventAnInstalledVersion() throws {
        let data = try WhiskyWineInstaller.installedVersionMarkerData(runtimeVersion: nil)

        XCTAssertNil(data)
    }

    func testRuntimeVersionComparisonOffersOnlyOlderInstalledVersions() {
        let installed = SemanticVersion(1, 0, 0)
        let available = SemanticVersion(1, 0, 1)
        let current = SemanticVersion(1, 0, 1)

        XCTAssertTrue(installed < available)
        XCTAssertFalse(current < available)
    }

    func testArchiveFilenameDoesNotDetermineSemanticVersion() throws {
        let data = try WhiskyWineInstaller.installedVersionMarkerData(runtimeVersion: "1.0.1")
        let versionInfo = try PropertyListDecoder().decode(WhiskyWineVersionInfo.self, from: try XCTUnwrap(data))
        let archiveName = "BourbonWine-1.0.0-macOS-x86_64.tar.gz"

        XCTAssertEqual(versionInfo.version, SemanticVersion(1, 0, 1))
        XCTAssertTrue(archiveName.contains("1.0.0"))
    }
}

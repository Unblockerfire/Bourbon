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

    func testBundledDiagnosticRuntimeRequiresArchiveAndValidMetadata() throws {
        let bundleURL = FileManager.default.temporaryDirectory
            .appending(path: "BourbonWineTests-\(UUID().uuidString)")
            .appendingPathExtension("bundle")
        let resourcesURL = bundleURL.appending(path: "Contents").appending(path: "Resources")
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": "com.unblockerfire.BourbonWineTests",
            "CFBundlePackageType": "BNDL"
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: infoPlist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: bundleURL.appending(path: "Contents").appending(path: "Info.plist"))
        try Data([0x1f, 0x8b]).write(
            to: resourcesURL.appending(path: "BourbonWineDiagnosticRuntime.tar.gz")
        )
        let metadata = """
        {
          "maximumMinimumMacOS": "14.0",
          "runtimeVersion": "1.0.2",
          "sourceAsset": "wine-devel-11.16-osx64.tar.xz",
          "sourceAssetSHA256": "test-sha256",
          "sourceRelease": "11.16",
          "sourceRepository": "Gcenx/macOS_Wine_builds",
          "wineVersion": "wine-11.16"
        }
        """
        try Data(metadata.utf8).write(
            to: resourcesURL.appending(path: "BourbonWineDiagnosticRuntime.json")
        )

        let bundle = try XCTUnwrap(Bundle(url: bundleURL))
        let bundledRuntime = try XCTUnwrap(WhiskyWineInstaller.bundledDiagnosticRuntime(in: bundle))

        XCTAssertEqual(bundledRuntime.info.runtimeVersion, "1.0.2")
        XCTAssertEqual(bundledRuntime.info.wineVersion, "wine-11.16")
        XCTAssertEqual(bundledRuntime.info.maximumMinimumMacOS, "14.0")
        XCTAssertEqual(bundledRuntime.archive.lastPathComponent, "BourbonWineDiagnosticRuntime.tar.gz")
    }
}

import CryptoKit
import XCTest
@testable import WhiskyKit

// swiftlint:disable file_length
// swiftlint:disable:next type_body_length
final class WhiskyWineRuntimeReadinessTests: XCTestCase {
    func testExpectedRuntimeDestinationUsesBundleIdentifier() {
        let root = URL(fileURLWithPath: "/isolated/Application Support")
        let destination = WhiskyWineInstaller.applicationFolder(
            bundleIdentifier: "com.unblockerfire.BourbonDiagnostic",
            applicationSupportRoot: root
        )

        XCTAssertEqual(
            destination.path,
            "/isolated/Application Support/com.unblockerfire.BourbonDiagnostic"
        )
    }

    func testProductionAndDiagnosticBundleIdentifiersResolveDistinctDestinations() {
        let root = URL(fileURLWithPath: "/isolated/Application Support")
        let production = WhiskyWineInstaller.applicationFolder(
            bundleIdentifier: "com.unblockerfire.Bourbon",
            applicationSupportRoot: root
        )
        let diagnostic = WhiskyWineInstaller.applicationFolder(
            bundleIdentifier: "com.unblockerfire.BourbonDiagnostic",
            applicationSupportRoot: root
        )

        XCTAssertNotEqual(production, diagnostic)
        XCTAssertEqual(production.lastPathComponent, "com.unblockerfire.Bourbon")
        XCTAssertEqual(diagnostic.lastPathComponent, "com.unblockerfire.BourbonDiagnostic")
    }

    func testCompletelyMissingRuntimeIsNotReady() throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }

        XCTAssertFalse(WhiskyWineInstaller.runtimeReadiness(in: fixture.applicationFolder).isReady)
    }

    func testDiscoveryReportsMissingRuntimeWithoutSchedulingDownload() async throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }

        let discovery = await WhiskyWineInstaller.discoverRuntime(
            in: fixture.applicationFolder,
            expectedRuntimeVersion: "1.0.2"
        )

        XCTAssertEqual(discovery.state, .missing)
        XCTAssertTrue(discovery.requiresDownload)
    }

    func testMarkerCannotMakeMissingWineReady() throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        try fixture.makeRuntime(version: "1.0.2", includeWine: false)

        let readiness = WhiskyWineInstaller.runtimeReadiness(in: fixture.applicationFolder)
        XCTAssertFalse(readiness.isReady)
        XCTAssertTrue(readiness.failures.contains(where: { $0.hasPrefix("missing:") }))
    }

    func testOldIncompatibleRuntimeIsNotReady() throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        try fixture.makeRuntime(version: "1.0.1")
        try fixture.writeMarker(version: "0.9.0")

        let readiness = WhiskyWineInstaller.runtimeReadiness(in: fixture.applicationFolder)
        XCTAssertFalse(readiness.isReady)
        XCTAssertTrue(readiness.failures.contains("installed_version_marker_mismatch"))
    }

    func testPartiallyExtractedRuntimeIsNotReady() throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        try fixture.makeRuntime(version: "1.0.2", includeNTDLL: false)

        XCTAssertFalse(WhiskyWineInstaller.runtimeReadiness(in: fixture.applicationFolder).isReady)
    }

    func testIncompleteRuntimeDiscoveryRequiresReplacement() async throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        try fixture.makeRuntime(version: "1.0.2", includeNTDLL: false)

        let discovery = await WhiskyWineInstaller.discoverRuntime(
            in: fixture.applicationFolder,
            expectedRuntimeVersion: "1.0.2"
        )

        XCTAssertEqual(discovery.state, .corruptOrIncomplete)
        XCTAssertTrue(discovery.requiresDownload)
    }

    func testRuntimeUpdaterInstallLifecycleReplacesOldRuntimeAndRunsWine() throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        try fixture.makeRuntime(version: "0.9.0")
        let archive = try fixture.archiveRuntime(version: "1.0.2")

        try WhiskyWineInstaller.install(from: archive, runtimeVersion: "1.0.2", into: fixture.applicationFolder)

        let readiness = WhiskyWineInstaller.runtimeReadiness(in: fixture.applicationFolder)
        XCTAssertTrue(readiness.isReady, readiness.failures.joined(separator: ", "))
        XCTAssertEqual(readiness.wineVersion?.trimmingCharacters(in: .whitespacesAndNewlines), "wine-11.16")
        XCTAssertTrue(WhiskyWineInstaller.hasRestorablePreviousRuntime(in: fixture.applicationFolder))
    }

    func testRestorePreviousRuntimeRetainsTheReplacedRuntime() throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        try fixture.makeRuntime(version: "1.0.1")
        let archive = try fixture.archiveRuntime(version: "1.0.2")
        try WhiskyWineInstaller.install(from: archive, runtimeVersion: "1.0.2", into: fixture.applicationFolder)

        try WhiskyWineInstaller.restorePreviousRuntime(in: fixture.applicationFolder)

        let version = WhiskyWineInstaller.whiskyWineVersion(in: fixture.applicationFolder)
            .map(String.init(describing:))
        XCTAssertEqual(version, "1.0.1")
        XCTAssertTrue(WhiskyWineInstaller.hasRestorablePreviousRuntime(in: fixture.applicationFolder))
    }

    func testFreshRuntimeExtractionPreservesExecutablePermissions() throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        let archive = try fixture.archiveRuntime(version: "1.0.2")

        try WhiskyWineInstaller.install(
            from: archive,
            runtimeVersion: "1.0.2",
            into: fixture.applicationFolder
        )

        let wine = fixture.applicationFolder.appending(path: "Libraries/Wine/bin/wine")
        let wineserver = fixture.applicationFolder.appending(path: "Libraries/Wine/bin/wineserver")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: wine.path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: wineserver.path))
    }

    func testManualDownloadArtifactInstallsWithoutRenamingOrRebuilding() async throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        let archive = try fixture.archiveRuntime(version: "1.0.2", compressed: false)

        XCTAssertEqual(archive.pathExtension, "tar")
        let persisted = try WhiskyWineInstaller.persistLocalArchive(at: archive)
        try WhiskyWineInstaller.install(
            from: persisted,
            runtimeVersion: nil,
            into: fixture.applicationFolder
        )

        XCTAssertTrue(WhiskyWineInstaller.runtimeReadiness(in: fixture.applicationFolder).isReady)
        XCTAssertEqual(
            WhiskyWineInstaller.whiskyWineVersion(in: fixture.applicationFolder)
                .map(String.init(describing:)),
            "1.0.2"
        )
        _ = try await WhiskyWineInstaller.retryInstalledRuntimeReadiness(in: fixture.applicationFolder)
    }

    func testManualArchiveFormatsIncludeBourbonDownloadFormats() {
        XCTAssertEqual(
            WhiskyWineInstaller.supportedManualArchiveExtensions,
            ["tar", "tar.gz", "tgz"]
        )
    }

    func testIncompleteExtractionNeverWritesInstalledMarker() throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        let archive = try fixture.archiveRuntime(version: "1.0.2", includeNTDLL: false)

        XCTAssertThrowsError(
            try WhiskyWineInstaller.install(
                from: archive,
                runtimeVersion: "1.0.2",
                into: fixture.applicationFolder
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.applicationFolder.appending(path: "Libraries/BourbonWineVersion.plist").path
        ))
    }

    func testSHA256MismatchRejectsArchiveBeforeInstallation() throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        let archive = try fixture.archiveRuntime(version: "1.0.2")

        XCTAssertThrowsError(
            try WhiskyWineInstaller.install(
                from: archive,
                runtimeVersion: "1.0.2",
                expectedSHA256: String(repeating: "0", count: 64),
                into: fixture.applicationFolder
            )
        ) { error in
            guard case WhiskyWineInstallerError.archiveChecksumMismatch = error else {
                return XCTFail("Expected archiveChecksumMismatch, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.applicationFolder.appending(path: "Libraries").path
        ))
    }

    func testFailedReplacementPreservesExistingValidRuntime() throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        try fixture.makeRuntime(version: "1.0.1")
        let invalidArchive = try fixture.archiveRuntime(version: "1.0.2", includeNTDLL: false)

        XCTAssertThrowsError(
            try WhiskyWineInstaller.install(
                from: invalidArchive,
                runtimeVersion: "1.0.2",
                into: fixture.applicationFolder
            )
        )
        XCTAssertEqual(
            WhiskyWineInstaller.whiskyWineVersion(in: fixture.applicationFolder).map(String.init(describing:)),
            "1.0.1"
        )
        XCTAssertTrue(WhiskyWineInstaller.runtimeReadiness(in: fixture.applicationFolder).isReady)
    }

    func testRuntimeInstallIsIdempotent() throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }

        for _ in 0..<2 {
            let archive = try fixture.archiveRuntime(version: "1.0.2")
            try WhiskyWineInstaller.install(
                from: archive,
                runtimeVersion: "1.0.2",
                into: fixture.applicationFolder
            )
        }

        let readiness = WhiskyWineInstaller.runtimeReadiness(in: fixture.applicationFolder)
        XCTAssertTrue(readiness.isReady, readiness.failures.joined(separator: ", "))
    }

    func testRetryOnlyRechecksInstalledRuntimeAndPreservesArchive() async throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        let archive = try fixture.archiveRuntime(version: "1.0.2")
        try WhiskyWineInstaller.install(from: archive, runtimeVersion: "1.0.2", into: fixture.applicationFolder)

        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
        let result = try await WhiskyWineInstaller.retryInstalledRuntimeReadiness(in: fixture.applicationFolder)
        XCTAssertEqual(result.version, "11.16")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.applicationFolder.appending(path: "Libraries/Wine/bin/wine").path
        ))
    }

    func testRetryReturnsGatekeeperBlockToRecoveryUI() async throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        try fixture.makeRuntime(version: "1.0.2")
        try fixture.writeWine(contents: "#!/bin/sh\necho 'Apple cannot verify wine' >&2\nexit 1\n")

        do {
            _ = try await WhiskyWineInstaller.retryInstalledRuntimeReadiness(in: fixture.applicationFolder)
            XCTFail("Expected Gatekeeper block")
        } catch let error as WineRuntimePreflightError {
            XCTAssertTrue(error.isGatekeeperBlocked)
        }
    }

    func testGatekeeperBlockedDiscoverySkipsDownloadOnRelaunch() async throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        try fixture.makeRuntime(version: "1.0.2")
        try fixture.writeWine(contents: "#!/bin/sh\necho 'Apple cannot verify wine' >&2\nexit 1\n")

        let discovery = await WhiskyWineInstaller.discoverRuntime(
            in: fixture.applicationFolder,
            expectedRuntimeVersion: "1.0.2"
        )

        XCTAssertEqual(discovery.state, .gatekeeperBlocked)
        XCTAssertFalse(discovery.requiresDownload)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.applicationFolder.appending(path: "Libraries/Wine/bin/wine").path
        ))

        // Simulate the user approving the same installed executable and reopening Bourbon.
        try fixture.writeWine(contents: "#!/bin/sh\necho wine-11.16\n")
        let reopened = await WhiskyWineInstaller.discoverRuntime(
            in: fixture.applicationFolder,
            expectedRuntimeVersion: "1.0.2"
        )
        XCTAssertEqual(reopened.state, .ready)
        XCTAssertFalse(reopened.requiresDownload)
    }

    func testGatekeeperBlockedArchiveInstallsToFinalLocationBeforeRecovery() async throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        let archive = try fixture.archiveRuntime(
            version: "1.0.2",
            wineContents: "#!/bin/sh\necho 'Apple cannot verify wine' >&2\nexit 1\n"
        )

        // Installation performs structural validation only; it must not throw
        // away the final runtime because macOS blocks its first execution.
        try WhiskyWineInstaller.install(from: archive, runtimeVersion: "1.0.2", into: fixture.applicationFolder)

        let discovery = await WhiskyWineInstaller.discoverRuntime(
            in: fixture.applicationFolder,
            expectedRuntimeVersion: "1.0.2"
        )
        XCTAssertEqual(discovery.state, .gatekeeperBlocked)
        XCTAssertFalse(discovery.requiresDownload)
    }

    func testInstalledUsableRuntimeIsReadyOnNextLaunch() async throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        try fixture.makeRuntime(version: "1.0.2")

        let discovery = await WhiskyWineInstaller.discoverRuntime(
            in: fixture.applicationFolder,
            expectedRuntimeVersion: "1.0.2"
        )

        XCTAssertEqual(discovery.state, .ready)
        XCTAssertFalse(discovery.requiresDownload)
    }

    func testStartupDiscoveryDoesNotApplyDiagnosticArchiveVersionToDownloadedRuntime() async throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        // This represents an approved runtime from the normal download channel,
        // while the app may also carry a newer diagnostic archive.
        try fixture.makeRuntime(version: "1.0.1")

        let discovery = await WhiskyWineInstaller.discoverRuntime(in: fixture.applicationFolder)

        XCTAssertEqual(discovery.state, .ready)
        XCTAssertFalse(discovery.requiresDownload)
    }

    func testRetryKeepsGenericRuntimeFailureDistinct() async throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        try fixture.makeRuntime(version: "1.0.2")
        try fixture.writeWine(contents: "#!/bin/sh\necho 'unexpected runtime failure' >&2\nexit 1\n")

        do {
            _ = try await WhiskyWineInstaller.retryInstalledRuntimeReadiness(in: fixture.applicationFolder)
            XCTFail("Expected generic preflight failure")
        } catch let error as WineRuntimePreflightError {
            XCTAssertFalse(error.isGatekeeperBlocked)
            XCTAssertEqual(error.diagnosticCode, "process_nonzero")
        }
    }

    func testRuntimeAcquisitionNeverDependsOnEmbeddedBundleContents() throws {
        let bundle = try fixtureBundleWithEmbeddedRuntime()
        defer { try? FileManager.default.removeItem(at: bundle.bundleURL) }

        XCTAssertNotNil(WhiskyWineInstaller.bundledDiagnosticRuntime(in: bundle))
        XCTAssertEqual(WhiskyWineInstaller.runtimeAcquisitionSource(in: bundle), .runtimeAPI)
    }

    // swiftlint:disable:next function_body_length
    func testManualDownloadArtifactStagesInstallsAndPreflightsUntouched() async throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        let sourceArchive = try fixture.archiveRuntime(version: "1.0.2")
        let sourceBytes = try Data(contentsOf: sourceArchive)
        let checksum = SHA256.hash(data: sourceBytes).map { String(format: "%02x", $0) }.joined()
        let sourceURL = try XCTUnwrap(URL(string: "https://runtime.example/BourbonWine-1.0.2.tar.gz"))
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: sourceURL,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/gzip"]
            )
        )
        let runtimeInfo = WhiskyWineInstaller.BourbonRuntimeInfo(
            version: "1.0.2",
            wineVersion: "wine-11.16",
            archiveName: "BourbonWine-1.0.2-macOS-x86_64.tar.gz",
            sha256: checksum,
            plistUrl: sourceURL,
            archiveUrl: sourceURL,
            expiresInSeconds: 900
        )
        let downloads = fixture.root.appending(path: "Downloads")

        let downloaded = try WhiskyWineInstaller.persistManualDownload(
            at: sourceArchive,
            response: response,
            runtimeInfo: runtimeInfo,
            downloadsDirectory: downloads
        )
        XCTAssertEqual(downloaded.lastPathComponent, runtimeInfo.archiveName)
        XCTAssertEqual(try Data(contentsOf: downloaded), sourceBytes)

        let selected = try WhiskyWineInstaller.persistLocalArchive(at: downloaded)
        XCTAssertEqual(try Data(contentsOf: selected), sourceBytes)
        try WhiskyWineInstaller.install(from: selected, into: fixture.applicationFolder)
        let readiness = try await WhiskyWineInstaller.retryInstalledRuntimeReadiness(
            in: fixture.applicationFolder
        )
        XCTAssertTrue(readiness.isReady, readiness.failures.joined(separator: ", "))
        XCTAssertEqual(
            WhiskyWineInstaller.whiskyWineVersion(in: fixture.applicationFolder).map(String.init(describing:)),
            "1.0.2"
        )
        XCTAssertEqual(readiness.wineVersion?.trimmingCharacters(in: .whitespacesAndNewlines), "wine-11.16")
    }

    func testExtendedAttributeDiagnosticsAreReadOnlyAndDistinguishStates() throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        let target = fixture.root.appending(path: "runtime-component")
        let original = Data("unchanged".utf8)
        try original.write(to: target)
        let present = try fixture.makeProbe(name: "xattr-present", output: "0081;Safari;", status: 0)
        let absent = try fixture.makeProbe(name: "xattr-absent", output: "No such xattr", status: 1)
        let unreadable = try fixture.makeProbe(name: "xattr-unreadable", output: "Permission denied", status: 1)

        XCTAssertEqual(
            WhiskyWineInstaller.extendedAttributeState(
                for: target,
                attribute: "com.apple.quarantine",
                xattrExecutableURL: present
            ),
            .present
        )
        XCTAssertEqual(
            WhiskyWineInstaller.extendedAttributeState(
                for: target,
                attribute: "com.apple.quarantine",
                xattrExecutableURL: absent
            ),
            .absent
        )
        XCTAssertEqual(
            WhiskyWineInstaller.extendedAttributeState(
                for: target,
                attribute: "com.apple.quarantine",
                xattrExecutableURL: unreadable
            ),
            .unreadable
        )
        XCTAssertEqual(
            WhiskyWineInstaller.extendedAttributeState(
                for: target,
                attribute: "com.apple.quarantine",
                xattrExecutableURL: fixture.root.appending(path: "missing-xattr")
            ),
            .unavailable
        )
        XCTAssertEqual(try Data(contentsOf: target), original)
    }

    func testDiagnosticAndProductionRuntimeStateCanCoexist() throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        let production = fixture.root.appending(path: "com.unblockerfire.Bourbon")
        let diagnostic = fixture.root.appending(path: "com.unblockerfire.BourbonDiagnostic")
        try fixture.makeRuntime(in: production, version: "1.0.0")
        try fixture.makeRuntime(in: diagnostic, version: "1.0.2")

        XCTAssertTrue(WhiskyWineInstaller.runtimeReadiness(in: production).isReady)
        XCTAssertTrue(WhiskyWineInstaller.runtimeReadiness(in: diagnostic).isReady)
        XCTAssertNotEqual(production, diagnostic)
    }

    func testPackagedDiagnosticUsesProductionRuntimeAcquisition() throws {
        guard let appPath = ProcessInfo.processInfo.environment["BOURBON_PACKAGED_DIAGNOSTIC_APP"] else {
            throw XCTSkip("Runs only when CI mounts the packaged diagnostic DMG.")
        }
        let bundle = try XCTUnwrap(Bundle(url: URL(fileURLWithPath: appPath)))

        XCTAssertEqual(bundle.bundleIdentifier, "com.unblockerfire.BourbonDiagnostic")
        XCTAssertNil(WhiskyWineInstaller.bundledDiagnosticRuntime(in: bundle))
        XCTAssertEqual(WhiskyWineInstaller.runtimeAcquisitionSource(in: bundle), .runtimeAPI)
        XCTAssertNil(bundle.url(forResource: "BourbonWineDiagnosticRuntime", withExtension: "tar.gz"))
    }

    private func fixtureBundleWithEmbeddedRuntime() throws -> Bundle {
        let bundleURL = FileManager.default.temporaryDirectory
            .appending(path: "BourbonAcquisitionTests-\(UUID().uuidString)")
            .appendingPathExtension("bundle")
        let resources = bundleURL.appending(path: "Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.unblockerfire.BourbonAcquisitionTests",
            "CFBundlePackageType": "BNDL"
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: bundleURL.appending(path: "Contents/Info.plist"))
        try Data([0x1f, 0x8b]).write(to: resources.appending(path: "BourbonWineDiagnosticRuntime.tar.gz"))
        let metadata = """
        {"maximumMinimumMacOS":"14.0","runtimeVersion":"1.0.2","sourceAsset":"fixture",
        "sourceAssetSHA256":"fixture","sourceRelease":"11.16","sourceRepository":"fixture",
        "wineVersion":"wine-11.16"}
        """
        try Data(metadata.utf8).write(to: resources.appending(path: "BourbonWineDiagnosticRuntime.json"))
        return try XCTUnwrap(Bundle(url: bundleURL))
    }
}

private final class RuntimeFixture {
    let root = FileManager.default.temporaryDirectory.appending(path: "BourbonRuntimeTests-\(UUID().uuidString)")
    var applicationFolder: URL { root.appending(path: "com.unblockerfire.BourbonDiagnostic") }

    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    func remove() { try? FileManager.default.removeItem(at: root) }

    func makeRuntime(
        in applicationFolder: URL? = nil,
        version: String,
        includeWine: Bool = true,
        includeNTDLL: Bool = true,
        wineContents: String = "#!/bin/sh\necho wine-11.16\n"
    ) throws {
        let libraries = (applicationFolder ?? self.applicationFolder).appending(path: "Libraries")
        let wineRoot = libraries.appending(path: "Wine")
        let bin = wineRoot.appending(path: "bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        if includeWine {
            try makeExecutable(at: bin.appending(path: "wine"), contents: wineContents)
        }
        try makeExecutable(at: bin.appending(path: "wineserver"), contents: "#!/bin/sh\necho wine-11.16\n")
        if includeNTDLL {
            let ntdll = wineRoot.appending(path: "lib/wine/x86_64-unix/ntdll.so")
            try FileManager.default.createDirectory(
                at: ntdll.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: ntdll)
        }
        let vulkan = wineRoot.appending(path: "lib/libvulkan.1.dylib")
        try FileManager.default.createDirectory(
            at: vulkan.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: vulkan)
        let manifest = "{\"runtimeVersion\":\"\(version)\",\"wineVersion\":\"wine-11.16\"}"
        try Data(manifest.utf8).write(to: libraries.appending(path: "BourbonWineRuntime.json"))
        let marker = try XCTUnwrap(WhiskyWineInstaller.installedVersionMarkerData(runtimeVersion: version))
        try marker.write(to: libraries.appending(path: "BourbonWineVersion.plist"))
    }

    func archiveRuntime(
        version: String,
        includeNTDLL: Bool = true,
        compressed: Bool = true,
        wineContents: String = "#!/bin/sh\necho wine-11.16\n"
    ) throws -> URL {
        let source = root.appending(path: "archive-source")
        if FileManager.default.fileExists(atPath: source.path) {
            try FileManager.default.removeItem(at: source)
        }
        try makeRuntime(
            in: source,
            version: version,
            includeNTDLL: includeNTDLL,
            wineContents: wineContents
        )
        let archive = root.appending(path: compressed ? "runtime.tar.gz" : "runtime.tar")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [compressed ? "-zcf" : "-cf", archive.path, "-C", source.path, "Libraries"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return archive
    }
    func writeMarker(version: String) throws {
        let marker = try XCTUnwrap(WhiskyWineInstaller.installedVersionMarkerData(runtimeVersion: version))
        try marker.write(to: applicationFolder.appending(path: "Libraries/BourbonWineVersion.plist"))
    }

    func writeWine(contents: String) throws {
        try makeExecutable(
            at: applicationFolder.appending(path: "Libraries/Wine/bin/wine"),
            contents: contents
        )
    }

    func makeProbe(name: String, output: String, status: Int32) throws -> URL {
        let probe = root.appending(path: name)
        try makeExecutable(at: probe, contents: "#!/bin/sh\nprintf '%s' '\(output)' >&2\nexit \(status)\n")
        return probe
    }

    private func makeExecutable(at url: URL, contents: String) throws {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

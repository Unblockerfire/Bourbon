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

    func testManualPlainTarArchiveInstallsWithoutRenaming() throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        let archive = try fixture.archiveRuntime(version: "1.0.2", compressed: false)

        XCTAssertEqual(archive.pathExtension, "tar")
        let persisted = try WhiskyWineInstaller.persistLocalArchive(at: archive)
        try WhiskyWineInstaller.install(
            from: persisted,
            runtimeVersion: "1.0.2",
            into: fixture.applicationFolder
        )

        XCTAssertTrue(WhiskyWineInstaller.runtimeReadiness(in: fixture.applicationFolder).isReady)
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

    func testPackagedDiagnosticArchiveInstallsIntoCleanApplicationSupport() throws {
        guard let archivePath = ProcessInfo.processInfo.environment["BOURBON_PACKAGED_DIAGNOSTIC_RUNTIME"] else {
            throw XCTSkip("Runs only when CI mounts the packaged diagnostic DMG.")
        }
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        let metadataPath = try XCTUnwrap(
            ProcessInfo.processInfo.environment["BOURBON_PACKAGED_DIAGNOSTIC_METADATA"]
        )
        let metadata = try JSONDecoder().decode(
            WhiskyWineInstaller.BundledDiagnosticRuntimeInfo.self,
            from: Data(contentsOf: URL(fileURLWithPath: metadataPath))
        )

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.applicationFolder.appending(path: "Libraries/Wine/bin/wine").path
        ))
        let persistedArchive = try WhiskyWineInstaller.persistLocalArchive(
            at: URL(fileURLWithPath: archivePath)
        )
        try WhiskyWineInstaller.install(
            from: persistedArchive,
            runtimeVersion: metadata.runtimeVersion,
            into: fixture.applicationFolder
        )

        let readiness = WhiskyWineInstaller.runtimeReadiness(in: fixture.applicationFolder)
        XCTAssertTrue(readiness.isReady, readiness.failures.joined(separator: ", "))
        XCTAssertEqual(
            readiness.wineVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
            metadata.wineVersion
        )
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.applicationFolder.appending(path: "Libraries/Wine/bin/wine").path
        ))
    }

    func testPackagedDiagnosticBundleBootstrapsFreshRuntime() throws {
        guard let appPath = ProcessInfo.processInfo.environment["BOURBON_PACKAGED_DIAGNOSTIC_APP"] else {
            throw XCTSkip("Runs only when CI mounts the packaged diagnostic DMG.")
        }
        let appURL = URL(fileURLWithPath: appPath)
        let bundle = try XCTUnwrap(Bundle(url: appURL))
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }

        XCTAssertEqual(bundle.bundleIdentifier, "com.unblockerfire.BourbonDiagnostic")
        XCTAssertNil(WhiskyWineInstaller.whiskyWineVersion(in: fixture.applicationFolder))
        let installedVersion = try WhiskyWineInstaller.installBundledDiagnosticRuntime(
            in: bundle,
            into: fixture.applicationFolder
        )

        XCTAssertEqual(installedVersion, "1.0.2")
        let readiness = WhiskyWineInstaller.runtimeReadiness(in: fixture.applicationFolder)
        XCTAssertTrue(readiness.isReady, readiness.failures.joined(separator: ", "))
        XCTAssertTrue(FileManager.default.isExecutableFile(
            atPath: fixture.applicationFolder.appending(path: "Libraries/Wine/bin/wine").path
        ))
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
        includeNTDLL: Bool = true
    ) throws {
        let libraries = (applicationFolder ?? self.applicationFolder).appending(path: "Libraries")
        let wineRoot = libraries.appending(path: "Wine")
        let bin = wineRoot.appending(path: "bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        if includeWine {
            try makeExecutable(at: bin.appending(path: "wine"), contents: "#!/bin/sh\necho wine-11.16\n")
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
        compressed: Bool = true
    ) throws -> URL {
        let source = root.appending(path: "archive-source")
        if FileManager.default.fileExists(atPath: source.path) {
            try FileManager.default.removeItem(at: source)
        }
        try makeRuntime(in: source, version: version, includeNTDLL: includeNTDLL)
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

    private func makeExecutable(at url: URL, contents: String) throws {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

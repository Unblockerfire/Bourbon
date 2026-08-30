import XCTest
@testable import WhiskyKit

final class WhiskyWineRuntimeReadinessTests: XCTestCase {
    func testCompletelyMissingRuntimeIsNotReady() throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }

        XCTAssertFalse(WhiskyWineInstaller.runtimeReadiness(in: fixture.applicationFolder).isReady)
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

    func testSuccessfulRuntimeReplacementIsTransactionalAndRunsWine() throws {
        let fixture = try RuntimeFixture()
        defer { fixture.remove() }
        try fixture.makeRuntime(version: "0.9.0")
        let archive = try fixture.archiveRuntime(version: "1.0.2")

        try WhiskyWineInstaller.install(from: archive, runtimeVersion: "1.0.2", into: fixture.applicationFolder)

        let readiness = WhiskyWineInstaller.runtimeReadiness(in: fixture.applicationFolder)
        XCTAssertTrue(readiness.isReady, readiness.failures.joined(separator: ", "))
        XCTAssertEqual(readiness.wineVersion?.trimmingCharacters(in: .whitespacesAndNewlines), "wine-11.16")
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

    func archiveRuntime(version: String) throws -> URL {
        let source = root.appending(path: "archive-source")
        try makeRuntime(in: source, version: version)
        let archive = root.appending(path: "runtime.tar.gz")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-zcf", archive.path, "-C", source.path, "Libraries"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return archive
    }

    func writeMarker(version: String) throws {
        let marker = try XCTUnwrap(WhiskyWineInstaller.installedVersionMarkerData(runtimeVersion: version))
        try marker.write(to: applicationFolder.appending(path: "Libraries/BourbonWineVersion.plist"))
    }

    private func makeExecutable(at url: URL, contents: String) throws {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

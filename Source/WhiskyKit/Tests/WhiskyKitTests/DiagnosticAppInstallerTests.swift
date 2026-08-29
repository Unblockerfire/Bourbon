import XCTest
@testable import WhiskyKit

final class DiagnosticAppInstallerTests: XCTestCase {
    func testOnlyDiagnosticBuildOutsideApplicationsRequiresInstallation() {
        let nonApplicationsPaths = [
            "/Volumes/Bourbon/Bourbon Diagnostic.app",
            "/private/var/folders/AppTranslocation/Bourbon Diagnostic.app",
            "/Users/tester/Downloads/Bourbon Diagnostic.app",
            "/Users/tester/Desktop/Bourbon Diagnostic.app",
            "/private/tmp/Bourbon Diagnostic.app"
        ]
        for path in nonApplicationsPaths {
            XCTAssertTrue(DiagnosticAppInstallationPolicy.requiresInstallation(
                bundleURL: URL(fileURLWithPath: path),
                displayName: "Bourbon Diagnostic"
            ))
        }
        XCTAssertFalse(DiagnosticAppInstallationPolicy.requiresInstallation(
            bundleURL: URL(fileURLWithPath: "/Applications/Bourbon Diagnostic.app"),
            displayName: "Bourbon Diagnostic"
        ))
        XCTAssertFalse(DiagnosticAppInstallationPolicy.requiresInstallation(
            bundleURL: URL(fileURLWithPath: "/Downloads/Bourbon.app"),
            displayName: "Bourbon"
        ))
    }

    func testDestinationCanNeverResolveToProductionBourbon() throws {
        let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let diagnostic = DiagnosticAppInstallationPolicy.destination(in: applications)

        XCTAssertEqual(diagnostic.path, "/Applications/Bourbon Diagnostic.app")
        XCTAssertNoThrow(try DiagnosticAppInstallationPolicy.validateDestination(
            diagnostic,
            applicationsDirectory: applications
        ))
        XCTAssertThrowsError(try DiagnosticAppInstallationPolicy.validateDestination(
            applications.appending(path: "Bourbon.app"),
            applicationsDirectory: applications
        ))
    }

    func testExistingCopyIsInspectedBeforeReplacement() throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        let existing = DiagnosticAppInstallationPolicy.destination(in: fixture.applications)
        try fixture.makeApp(at: existing, commit: "old-commit", payload: "old")

        let inspected = DiagnosticAppInstallationPolicy.inspectExistingCopy(
            in: fixture.applications,
            fileManager: .default
        )

        XCTAssertEqual(inspected?.identity.gitCommit, "old-commit")
        XCTAssertEqual(inspected?.identity.versionDisplay, "2.0.19 (100045)")
    }

    func testCopyRequiresConsentAndNeverOverwritesProductionApp() throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        let source = fixture.root.appending(path: "Bourbon Diagnostic.app")
        let diagnostic = DiagnosticAppInstallationPolicy.destination(in: fixture.applications)
        let production = fixture.applications.appending(path: "Bourbon.app")
        try fixture.makeApp(at: source, commit: "new-commit", payload: "new")
        try fixture.makeApp(at: diagnostic, commit: "old-commit", payload: "old")
        try fixture.makeApp(at: production, commit: "production", payload: "production")
        let copier = DiagnosticAppBundleCopier(applicationsDirectory: fixture.applications)

        XCTAssertThrowsError(try copier.copy(source: source, replaceExisting: false) { _ in }) { error in
            XCTAssertEqual(error as? DiagnosticAppInstallationError, .destinationExists)
        }
        XCTAssertEqual(try fixture.payload(at: diagnostic), "old")

        let installed = try copier.copy(source: source, replaceExisting: true) { _ in }
        XCTAssertEqual(installed, diagnostic)
        XCTAssertEqual(try fixture.payload(at: diagnostic), "new")
        XCTAssertEqual(try fixture.payload(at: production), "production")
    }

    func testCopyProgressUsesCopiedBytesAndFiles() throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        let source = fixture.root.appending(path: "Bourbon Diagnostic.app")
        try fixture.makeApp(at: source, commit: "commit", payload: String(repeating: "x", count: 32_768))
        let copier = DiagnosticAppBundleCopier(applicationsDirectory: fixture.applications)
        var reports: [DiagnosticCopyProgress] = []

        _ = try copier.copy(source: source, replaceExisting: false) { reports.append($0) }

        XCTAssertEqual(reports.first?.fractionCompleted, 0)
        XCTAssertEqual(reports.last?.fractionCompleted, 1)
        XCTAssertEqual(reports.last?.bytesCopied, reports.last?.totalBytes)
        XCTAssertEqual(reports.last?.filesCopied, reports.last?.totalFiles)
    }

    func testInstalledRelaunchPathMustBeExactApplicationsDestination() {
        XCTAssertTrue(DiagnosticAppInstallationPolicy.isInstalledDestination(
            URL(fileURLWithPath: "/Applications/Bourbon Diagnostic.app")
        ))
        XCTAssertFalse(DiagnosticAppInstallationPolicy.isInstalledDestination(
            URL(fileURLWithPath: "/private/var/folders/AppTranslocation/Bourbon Diagnostic.app")
        ))
        XCTAssertFalse(DiagnosticAppInstallationPolicy.isInstalledDestination(
            URL(fileURLWithPath: "/Applications/Bourbon.app")
        ))
    }
}

private final class InstallerFixture {
    let root: URL
    let applications: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        applications = root.appending(path: "Applications", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func makeApp(at url: URL, commit: String, payload: String) throws {
        let contents = url.appending(path: "Contents", directoryHint: .isDirectory)
        let resources = contents.appending(path: "Resources", directoryHint: .isDirectory)
        let executables = contents.appending(path: "MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: executables, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleDisplayName": "Bourbon Diagnostic",
            "CFBundleExecutable": "Bourbon",
            "CFBundleShortVersionString": "2.0.19",
            "CFBundleVersion": "100045"
        ]
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: contents.appending(path: "Info.plist"))
        let identity = DiagnosticBuildIdentity(
            gitCommit: commit,
            marketingVersion: "2.0.19",
            buildNumber: "100045",
            buildDateUTC: "2026-08-29T00:00:00Z"
        )
        try JSONEncoder().encode(identity).write(to: resources.appending(path: "BuildInfo.json"))
        try Data(payload.utf8).write(to: resources.appending(path: "payload.txt"))
        let executable = executables.appending(path: "Bourbon")
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    func payload(at app: URL) throws -> String {
        let data = try Data(contentsOf: app.appending(path: "Contents/Resources/payload.txt"))
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}

//
//  RuntimeWineBinaryTests.swift
//  WhiskyKitTests
//

import XCTest
@testable import WhiskyKit

final class RuntimeWineBinaryTests: XCTestCase {
    private let binFolder = URL(fileURLWithPath: "/runtime/Libraries/Wine/bin")

    func testUsesWineLauncherShippedByCurrentBourbonRuntime() {
        let existingPaths = Set([
            "/runtime/Libraries/Wine/bin/wine",
            "/runtime/Libraries/Wine/bin/wineserver"
        ])

        let binary = WhiskyWineInstaller.runtimeWineBinary(in: binFolder) {
            existingPaths.contains($0)
        }

        XCTAssertEqual(binary.lastPathComponent, "wine")
    }

    func testPrefersWine64WhenRuntimeProvidesBothLaunchers() {
        let existingPaths = Set([
            "/runtime/Libraries/Wine/bin/wine",
            "/runtime/Libraries/Wine/bin/wine64"
        ])

        let binary = WhiskyWineInstaller.runtimeWineBinary(in: binFolder) {
            existingPaths.contains($0)
        }

        XCTAssertEqual(binary.lastPathComponent, "wine64")
    }

    func testFallsBackToStandardWinePathForActionableLaunchFailure() {
        let binary = WhiskyWineInstaller.runtimeWineBinary(in: binFolder) { _ in false }

        XCTAssertEqual(binary.path, "/runtime/Libraries/Wine/bin/wine")
    }
}

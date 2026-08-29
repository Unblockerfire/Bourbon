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

        let binary = RuntimeWineBinary.resolve(in: binFolder) {
            existingPaths.contains($0)
        }

        XCTAssertEqual(binary.lastPathComponent, "wine")
    }

    func testPrefersWineWhenRuntimeProvidesBothLaunchers() {
        let existingPaths = Set([
            "/runtime/Libraries/Wine/bin/wine",
            "/runtime/Libraries/Wine/bin/wine64"
        ])

        let binary = RuntimeWineBinary.resolve(in: binFolder) {
            existingPaths.contains($0)
        }

        XCTAssertEqual(binary.lastPathComponent, "wine")
    }

    func testFallsBackToWine64ForSupportedAlternateRuntime() {
        let existingPaths = Set(["/runtime/Libraries/Wine/bin/wine64"])
        let binary = RuntimeWineBinary.resolve(in: binFolder) {
            existingPaths.contains($0)
        }

        XCTAssertEqual(binary.lastPathComponent, "wine64")
    }

    func testReturnsWinePathForActionableLaunchFailureWhenNeitherExists() {
        let binary = RuntimeWineBinary.resolve(in: binFolder) { _ in false }

        XCTAssertEqual(binary.path, "/runtime/Libraries/Wine/bin/wine")
    }
}

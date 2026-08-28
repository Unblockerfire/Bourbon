//
//  WineSemanticVersionTests.swift
//  WhiskyKitTests
//

import XCTest
@testable import WhiskyKit

final class WineSemanticVersionTests: XCTestCase {
    func testNormalizesExactCurrentProductionWineCommandOutput() {
        let output = "wine-11.11-199-ge3bb4552d76\n"

        XCTAssertEqual(
            WineSemanticVersion.versionToken(from: output),
            "11.11-199-ge3bb4552d76"
        )
        XCTAssertEqual(
            WineSemanticVersion.parse(output)?.description,
            "11.11.0-199-ge3bb4552d76"
        )
    }

    func testNormalizesWineCXVersionDescription() {
        let output = "wine-8.0-rc1 (CrossOver build)\r\n"

        XCTAssertEqual(WineSemanticVersion.versionToken(from: output), "8.0-rc1")
        XCTAssertEqual(WineSemanticVersion.parse(output)?.description, "8.0.0-rc1")
    }

    func testParsesCurrentProductionRuntimeVersion() {
        let version = WineSemanticVersion.parse("11.11-199-ge3bb4552d76")

        XCTAssertEqual(version?.description, "11.11.0-199-ge3bb4552d76")
    }

    func testNormalizesTwoComponentStableVersion() {
        let version = WineSemanticVersion.parse("11.11")

        XCTAssertEqual(version?.description, "11.11.0")
    }

    func testNormalizesTwoComponentReleaseCandidate() {
        let version = WineSemanticVersion.parse("8.0-rc1")

        XCTAssertEqual(version?.description, "8.0.0-rc1")
    }

    func testLeavesSemanticVersionUnchanged() {
        let version = WineSemanticVersion.parse("10.2.3-beta.1+build.4")

        XCTAssertEqual(version?.description, "10.2.3-beta.1+build.4")
    }

    func testRejectsMalformedVersion() {
        XCTAssertNil(WineSemanticVersion.parse("Wine development build"))
        XCTAssertNil(WineSemanticVersion.parse("11"))
        XCTAssertNil(WineSemanticVersion.parse("11.x"))
        XCTAssertNil(WineSemanticVersion.parse("wine-"))
        XCTAssertNil(WineSemanticVersion.parse(""))
    }

    func testInvalidWineOutputErrorIsPublicSafe() {
        XCTAssertThrowsError(try WineSemanticVersion.requireVersionToken(from: "")) { error in
            XCTAssertEqual(error as? WineVersionError, .invalidOutput)
        }
        XCTAssertEqual(
            WineVersionError.invalidOutput.errorDescription,
            "Wine did not return a recognizable version."
        )
    }
}

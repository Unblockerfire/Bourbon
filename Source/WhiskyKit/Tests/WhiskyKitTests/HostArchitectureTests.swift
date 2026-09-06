import XCTest
@testable import WhiskyKit

final class HostArchitectureTests: XCTestCase {
    func testAppleSiliconHardwareRequiresRosettaForBourbonWine() {
        let host = HostArchitecture.detect(arm64Hardware: 1)

        XCTAssertEqual(host, .appleSilicon)
        XCTAssertTrue(host.requiresRosettaForX86Runtime)
    }

    func testIntelHardwareDoesNotRequireRosettaForBourbonWine() {
        let host = HostArchitecture.detect(arm64Hardware: 0)

        XCTAssertEqual(host, .intel)
        XCTAssertFalse(host.requiresRosettaForX86Runtime)
    }

    func testMissingArm64HardwareCapabilityIsTreatedAsIntel() {
        XCTAssertEqual(HostArchitecture.detect(arm64Hardware: nil), .intel)
    }

    func testIntelRuntimeReadinessDoesNotDependOnRosetta() {
        XCTAssertTrue(
            Rosetta2.bourbonWineDependenciesAreReady(
                rosettaInstalled: false,
                runtimeReady: true,
                hostArchitecture: .intel
            )
        )
    }

    func testAppleSiliconRuntimeReadinessRequiresRosetta() {
        XCTAssertFalse(
            Rosetta2.bourbonWineDependenciesAreReady(
                rosettaInstalled: false,
                runtimeReady: true,
                hostArchitecture: .appleSilicon
            )
        )
    }
}

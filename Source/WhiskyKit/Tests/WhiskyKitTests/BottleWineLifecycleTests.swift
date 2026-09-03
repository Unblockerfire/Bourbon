import XCTest
@testable import WhiskyKit

final class BottleWineLifecycleTests: XCTestCase {
    func testOrphanedWineChildIsStillOwnedByItsBottlePrefix() {
        let bottle = Bottle(
            bottleUrl: URL(fileURLWithPath: "/private/var/folders/test/11111111-1111-1111-1111-111111111111")
        )
        BottleWineLifecycle.shared.registerLaunch(
            bottle: bottle,
            pid: 17471,
            wineserver: URL(fileURLWithPath: "/private/runtime/bin/wineserver")
        )

        let snapshot = BottleWineLifecycle.shared.snapshot(for: bottle)
        XCTAssertEqual(snapshot?.bottleIdentifier, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(snapshot?.prefixIdentifier, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(snapshot?.launchPID, 17471)
        XCTAssertEqual(snapshot?.wineserverIdentifier, "wineserver")
        // The affected-Mac Steam process had PPID 1. No parent-PID state exists
        // in the lifecycle record, so reparenting cannot move it into another bottle.
    }

    func testCleanupStateIsIsolatedPerBottle() {
        let first = Bottle(bottleUrl: URL(fileURLWithPath: "/tmp/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
        let second = Bottle(bottleUrl: URL(fileURLWithPath: "/tmp/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"))
        let wineserver = URL(fileURLWithPath: "/runtime/bin/wineserver")
        BottleWineLifecycle.shared.registerLaunch(bottle: first, pid: 101, wineserver: wineserver)
        BottleWineLifecycle.shared.registerLaunch(bottle: second, pid: 202, wineserver: wineserver)
        BottleWineLifecycle.shared.beginCleanup(bottle: first, reason: "installer_cancelled", wineserver: wineserver)
        BottleWineLifecycle.shared.finishCleanup(bottle: first, result: "prefix_terminated")

        XCTAssertEqual(BottleWineLifecycle.shared.snapshot(for: first)?.cleanupResult, "prefix_terminated")
        XCTAssertNil(BottleWineLifecycle.shared.snapshot(for: second)?.cleanupResult)
        XCTAssertEqual(BottleWineLifecycle.shared.snapshot(for: second)?.launchPID, 202)
    }

    func testIntentionalTerminationIsScopedAndClearedByANewLaunch() {
        let first = Bottle(
            bottleUrl: URL(fileURLWithPath: "/tmp/cccccccc-cccc-cccc-cccc-cccccccccccc")
        )
        let second = Bottle(
            bottleUrl: URL(fileURLWithPath: "/tmp/dddddddd-dddd-dddd-dddd-dddddddddddd")
        )
        let wineserver = URL(fileURLWithPath: "/runtime/bin/wineserver")

        BottleWineLifecycle.shared.registerLaunch(bottle: first, pid: 303, wineserver: wineserver)
        BottleWineLifecycle.shared.beginCleanup(
            bottle: first,
            reason: "program_terminated",
            wineserver: wineserver
        )

        XCTAssertTrue(BottleWineLifecycle.shared.hasIntentionalTermination(for: first))
        XCTAssertFalse(BottleWineLifecycle.shared.hasIntentionalTermination(for: second))

        BottleWineLifecycle.shared.beginCleanup(
            bottle: second,
            reason: "program_launch_failed",
            wineserver: wineserver
        )
        XCTAssertFalse(BottleWineLifecycle.shared.hasIntentionalTermination(for: second))

        BottleWineLifecycle.shared.registerLaunch(bottle: first, pid: 404, wineserver: wineserver)

        XCTAssertFalse(BottleWineLifecycle.shared.hasIntentionalTermination(for: first))
        XCTAssertNil(BottleWineLifecycle.shared.snapshot(for: first)?.cleanupResult)
    }
}

import Foundation
import XCTest
@testable import WhiskyKit

final class RuntimeProcessTimeoutTests: XCTestCase {
    func testBoundedProcessCapturesSuccessfulOutput() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf 'wine-11.16'"]

        let result = try RuntimeReadiness.runBounded(process: process, timeout: 2)

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.reason, "exit")
        XCTAssertEqual(result.output, "wine-11.16")
    }

    func testBoundedProcessTerminatesOnTimeout() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["10"]

        let started = Date()
        XCTAssertThrowsError(try RuntimeReadiness.runBounded(process: process, timeout: 0.1)) { error in
            XCTAssertEqual(error as? RuntimeWineVersionError, .timeout(seconds: 0.1))
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testBoundedProcessTerminatesOnCancellation() async throws {
        let worker = Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sleep")
            process.arguments = ["10"]
            return try RuntimeReadiness.runBounded(process: process, timeout: 30)
        }
        try await Task.sleep(for: .milliseconds(100))
        worker.cancel()

        do {
            _ = try await worker.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected terminal branch.
        } catch {
            XCTFail("Expected CancellationError, received \(error)")
        }
    }

    func testBoundedProcessReportsNonzeroTerminationWithoutHanging() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf 'blocked' >&2; exit 7"]

        let result = try RuntimeReadiness.runBounded(process: process, timeout: 2)

        XCTAssertEqual(result.status, 7)
        XCTAssertEqual(result.output, "blocked")
    }
}

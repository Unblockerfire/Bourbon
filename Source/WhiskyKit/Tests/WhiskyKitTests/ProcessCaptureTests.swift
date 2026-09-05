import Foundation
import XCTest
@testable import WhiskyKit

final class ProcessCaptureTests: XCTestCase {
    func testCapturedLaunchLogsExactProcessRunBoundary() async throws {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("log")
        XCTAssertTrue(FileManager.default.createFile(atPath: logURL.path, contents: nil))
        let logHandle = try FileHandle(forWritingTo: logURL)
        defer { try? FileManager.default.removeItem(at: logURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exit 0"]
        process.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
        process.environment = ["WINEPREFIX": "/tmp/Test Bottle", "TEST_TOKEN": "private"]

        for await _ in try process.runStream(name: "captured-boundary", fileHandle: logHandle) {}

        let log = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(log.contains("Process.run boundary"))
        XCTAssertTrue(log.contains("Process executableURL: /bin/sh"))
        XCTAssertTrue(log.contains("Process argv: [\"-c\", \"exit 0\"]"))
        XCTAssertTrue(log.contains("Process working directory: /tmp"))
        XCTAssertTrue(log.contains("TEST_TOKEN=<redacted>"))
        XCTAssertTrue(log.contains("WINEPREFIX=/tmp/Test Bottle"))
        XCTAssertTrue(log.contains("Standard output attachment: Pipe"))
        XCTAssertTrue(log.contains("Standard error attachment: Pipe"))
        XCTAssertTrue(log.contains("Termination handler attached: true"))
        XCTAssertTrue(log.contains("Launch mode: captured"))
    }

    func testNormalGUILaunchLogsInheritedOutputBoundary() async throws {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("log")
        XCTAssertTrue(FileManager.default.createFile(atPath: logURL.path, contents: nil))
        let logHandle = try FileHandle(forWritingTo: logURL)
        defer { try? FileManager.default.removeItem(at: logURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exit 0"]

        for await _ in try process.runUncaptured(name: "gui-boundary", fileHandle: logHandle) {}

        let log = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(log.contains("Standard output attachment: <nil>"))
        XCTAssertTrue(log.contains("Standard error attachment: <nil>"))
        XCTAssertTrue(log.contains("Termination handler attached: true"))
        XCTAssertTrue(log.contains("Launch mode: normalGUI"))
    }
}

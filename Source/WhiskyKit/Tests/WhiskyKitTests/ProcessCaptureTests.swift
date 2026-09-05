import Foundation
import XCTest
@testable import WhiskyKit

final class ProcessCaptureTests: XCTestCase {
    func testCapturesOutputFromFastFailingProcess() async throws {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("log")
        XCTAssertTrue(FileManager.default.createFile(atPath: logURL.path, contents: nil))
        let logHandle = try FileHandle(forWritingTo: logURL)
        defer { try? FileManager.default.removeItem(at: logURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf 'captured-out'; printf 'captured-error' >&2; exit 1"]

        var output = ""
        var errorOutput = ""
        var status: Int32?
        for await event in try process.runStream(name: "fast-failure", fileHandle: logHandle) {
            switch event {
            case .message(let value):
                output.append(value)
            case .error(let value):
                errorOutput.append(value)
            case .terminated(let finishedProcess):
                status = finishedProcess.terminationStatus
            case .started:
                break
            }
        }

        let log = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertEqual(status, 1)
        XCTAssertEqual(output, "captured-out")
        XCTAssertEqual(errorOutput, "captured-error")
        XCTAssertTrue(log.contains("Safe stdout/stderr excerpt"))
        XCTAssertTrue(log.contains("captured-error"))
    }

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
        XCTAssertTrue(log.contains("WINEPREFIX=/tmp/Test Bottle"))
        XCTAssertFalse(log.contains("TEST_TOKEN"))
        XCTAssertFalse(log.contains("private"))
        XCTAssertTrue(log.contains("Standard output attachment:"))
        XCTAssertTrue(log.contains("Standard error attachment:"))
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
        process.environment = [
            "WINEPREFIX": "/tmp/Test Bottle",
            "PRIVATE_TOKEN": "must-not-appear"
        ]

        for await _ in try process.runUncaptured(name: "gui-boundary", fileHandle: logHandle) {}

        let log = try String(contentsOf: logURL, encoding: .utf8)
        let outputAttachment = try XCTUnwrap(log.line(containing: "Standard output attachment:"))
        let errorAttachment = try XCTUnwrap(log.line(containing: "Standard error attachment:"))
        XCTAssertFalse(outputAttachment.contains("Pipe"))
        XCTAssertFalse(errorAttachment.contains("Pipe"))
        XCTAssertTrue(log.contains("Termination handler attached: true"))
        XCTAssertTrue(log.contains("Launch mode: normalGUI"))
        XCTAssertTrue(log.contains("WINEPREFIX=/tmp/Test Bottle"))
        XCTAssertFalse(log.contains("PRIVATE_TOKEN"))
        XCTAssertFalse(log.contains("must-not-appear"))
    }
}

private extension String {
    func line(containing value: String) -> String? {
        split(separator: "\n").map(String.init).first { $0.contains(value) }
    }
}

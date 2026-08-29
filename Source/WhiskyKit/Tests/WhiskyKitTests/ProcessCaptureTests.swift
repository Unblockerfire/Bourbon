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
}

//
//  BourbonLicenseServiceFailureTests.swift
//  WhiskyKitTests
//

import Foundation
@testable import WhiskyKit
import XCTest

final class BourbonLicenseServiceFailureTests: XCTestCase {
    func testTransportFailuresHaveSpecificPrivacySafeCodes() {
        XCTAssertEqual(
            BourbonLicenseServiceFailure.classifyTransportError(URLError(.timedOut)),
            .timeout
        )
        XCTAssertEqual(
            BourbonLicenseServiceFailure.classifyTransportError(URLError(.notConnectedToInternet)),
            .offline
        )
        XCTAssertEqual(
            BourbonLicenseServiceFailure.classifyTransportError(URLError(.cannotFindHost)),
            .dns
        )
        XCTAssertEqual(
            BourbonLicenseServiceFailure.classifyTransportError(URLError(.secureConnectionFailed)),
            .tls
        )
    }

    func testDiagnosticCodesContainNoRequestOrCredentialData() {
        XCTAssertEqual(BourbonLicenseServiceFailure.timeout.diagnosticCode, "transport_timeout")
        XCTAssertEqual(BourbonLicenseServiceFailure.httpStatus(503).diagnosticCode, "http_503")
        XCTAssertEqual(
            BourbonLicenseServiceFailure.invalidPayload("missing_checkedAt").diagnosticCode,
            "decode_missing_checkedAt"
        )
    }

    func testHTTPFailuresRemainActionable() {
        XCTAssertTrue(BourbonLicenseServiceFailure.httpStatus(429).userMessage.contains("too many"))
        XCTAssertTrue(BourbonLicenseServiceFailure.httpStatus(503).userMessage.contains("temporarily unavailable"))
    }
}

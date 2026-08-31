//
//  BourbonLicenseServiceFailure.swift
//  WhiskyKit
//

import Foundation

/// A privacy-safe classification of failures returned while contacting the
/// Bourbon license service. The classification intentionally carries no URL,
/// license identifier, token, response body, or localized system text.
public enum BourbonLicenseServiceFailure: Error, Equatable, Sendable {
    case cancelled
    case timeout
    case offline
    case dns
    case tls
    case transport(Int)
    case invalidHTTPResponse
    case httpStatus(Int)
    case invalidPayload(String)

    public static func classifyTransportError(_ error: Error) -> Self {
        if error is CancellationError {
            return .cancelled
        }

        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return .transport(nsError.code)
        }

        let code = URLError.Code(rawValue: nsError.code)
        switch code {
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .timeout
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .offline
        case .cannotFindHost, .dnsLookupFailed:
            return .dns
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired:
            return .tls
        default:
            return .transport(nsError.code)
        }
    }

    public var diagnosticCode: String {
        switch self {
        case .cancelled:
            return "cancelled"
        case .timeout:
            return "transport_timeout"
        case .offline:
            return "transport_offline"
        case .dns:
            return "transport_dns"
        case .tls:
            return "transport_tls"
        case .transport(let code):
            return "transport_\(code)"
        case .invalidHTTPResponse:
            return "response_not_http"
        case .httpStatus(let status):
            return "http_\(status)"
        case .invalidPayload(let stage):
            return "decode_\(stage)"
        }
    }

    public var userMessage: String {
        switch self {
        case .cancelled:
            return "License validation was cancelled. Select Try Again when you are ready."
        case .timeout:
            return "The license service took too long to respond. Select Try Again to reconnect."
        case .offline:
            return "This Mac appears to be offline. Check its connection, then select Try Again."
        case .dns:
            return "This Mac could not find the Bourbon license service. Check DNS or network settings, then try again."
        case .tls:
            return "A secure connection to the Bourbon license service could not be established. " +
                "Check the Mac’s date, network, or security software."
        case .transport:
            return "Bourbon could not complete the connection to the license service. Select Try Again."
        case .invalidHTTPResponse, .invalidPayload:
            return "Bourbon received an unreadable response from the license service. " +
                "Select Try Again and send the diagnostic code if it continues."
        case .httpStatus(let status):
            if status == 429 {
                return "The license service is receiving too many requests. Wait a moment, then select Try Again."
            }
            if status >= 500 {
                return "The Bourbon license service is temporarily unavailable. Select Try Again shortly."
            }
            return "The license service rejected the request (HTTP \(status)). " +
                "Select Try Again or contact Bourbon support."
        }
    }
}

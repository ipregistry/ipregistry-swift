// Copyright 2019 Ipregistry (https://ipregistry.co).
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

/// A strongly typed Ipregistry API error code.
///
/// `ErrorCode` wraps the raw code string, so codes introduced by the API after
/// this library was released are preserved rather than lost. Compare against
/// the provided constants:
///
/// ```swift
/// catch let error as APIError where error.code == .insufficientCredits {
///     // handle exhausted credits
/// }
/// ```
///
/// See [ipregistry.co/docs/errors](https://ipregistry.co/docs/errors) for the
/// authoritative list.
public struct ErrorCode: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static let badRequest = ErrorCode(rawValue: "BAD_REQUEST")
    public static let disabledAPIKey = ErrorCode(rawValue: "DISABLED_API_KEY")
    public static let forbiddenIP = ErrorCode(rawValue: "FORBIDDEN_IP")
    public static let forbiddenOrigin = ErrorCode(rawValue: "FORBIDDEN_ORIGIN")
    public static let forbiddenIPOrigin = ErrorCode(rawValue: "FORBIDDEN_IP_ORIGIN")
    public static let internalError = ErrorCode(rawValue: "INTERNAL")
    public static let insufficientCredits = ErrorCode(rawValue: "INSUFFICIENT_CREDITS")
    public static let invalidAPIKey = ErrorCode(rawValue: "INVALID_API_KEY")
    public static let invalidASN = ErrorCode(rawValue: "INVALID_ASN")
    public static let invalidFilterSyntax = ErrorCode(rawValue: "INVALID_FILTER_SYNTAX")
    public static let invalidIPAddress = ErrorCode(rawValue: "INVALID_IP_ADDRESS")
    public static let missingAPIKey = ErrorCode(rawValue: "MISSING_API_KEY")
    public static let reservedASN = ErrorCode(rawValue: "RESERVED_ASN")
    public static let reservedIPAddress = ErrorCode(rawValue: "RESERVED_IP_ADDRESS")
    public static let tooManyASNs = ErrorCode(rawValue: "TOO_MANY_ASNS")
    public static let tooManyIPs = ErrorCode(rawValue: "TOO_MANY_IPS")
    public static let tooManyRequests = ErrorCode(rawValue: "TOO_MANY_REQUESTS")
    public static let tooManyUserAgents = ErrorCode(rawValue: "TOO_MANY_USER_AGENTS")
    public static let unknownASN = ErrorCode(rawValue: "UNKNOWN_ASN")
}

/// An error reported by the Ipregistry API, such as an invalid IP address, an
/// exhausted credit balance, or throttling.
///
/// In batch lookups, an `APIError` may also describe the failure of a single
/// entry rather than the whole request; see
/// ``IpregistryClient/lookupBatch(_:options:)``.
public struct APIError: Error, Hashable, Sendable {
    /// The error code returned by the API, or `nil` when the response did not
    /// carry a recognizable error payload (for example an unexpected HTTP
    /// status with a non-JSON body).
    public let code: ErrorCode?

    /// A human-readable description of the error.
    public let message: String

    /// A suggestion on how to resolve the error, when available.
    public let resolution: String

    /// Creates an API error. Mostly useful for testing code that consumes
    /// this library.
    public init(code: ErrorCode? = nil, message: String = "", resolution: String = "") {
        self.code = code
        self.message = message
        self.resolution = resolution
    }
}

extension APIError: LocalizedError, CustomStringConvertible {
    public var description: String {
        var text = "ipregistry: "
        text += message.isEmpty ? "API error" : message
        if let code {
            text += " (\(code.rawValue))"
        }
        if !resolution.isEmpty {
            text += ": \(resolution)"
        }
        return text
    }

    public var errorDescription: String? { description }
}

/// An error that occurred on the client side rather than being reported by the
/// API, such as a network failure, request cancellation, or a response that
/// cannot be decoded.
public struct ClientError: Error, Sendable {
    /// A human-readable description of the failure.
    public let message: String

    /// The underlying cause, when any (for example a `URLError` or a
    /// `DecodingError`).
    public let underlyingError: (any Error)?

    /// Creates a client error. Mostly useful for testing code that consumes
    /// this library.
    public init(message: String, underlyingError: (any Error)? = nil) {
        self.message = message
        self.underlyingError = underlyingError
    }
}

extension ClientError: LocalizedError, CustomStringConvertible {
    public var description: String {
        if let underlyingError {
            return "ipregistry: \(message): \(underlyingError)"
        }
        return "ipregistry: \(message)"
    }

    public var errorDescription: String? { description }
}

/// The JSON error body returned by the API.
struct APIErrorPayload: Decodable {
    let code: String?
    let message: String?
    let resolution: String?

    var apiError: APIError {
        APIError(
            code: code.map(ErrorCode.init(rawValue:)),
            message: message ?? "",
            resolution: resolution ?? ""
        )
    }
}

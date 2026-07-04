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

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// An HTTP request issued by an ``IpregistryClient``.
public struct HTTPTransportRequest: Sendable {
    /// The HTTP method, `"GET"` or `"POST"`.
    public var method: String

    /// The absolute request URL, including query parameters.
    public var url: URL

    /// The request headers.
    public var headers: [String: String]

    /// The request body, present on `POST` requests.
    public var body: Data?

    /// The per-request timeout, in seconds, from
    /// ``IpregistryClient/Configuration/timeout``.
    public var timeout: TimeInterval

    public init(
        method: String,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 15
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

/// An HTTP response received by an ``IpregistryClient``.
public struct HTTPTransportResponse: Sendable {
    /// The HTTP status code.
    public var statusCode: Int

    /// The response headers, keyed by lowercase header name.
    public var headers: [String: String]

    /// The raw response body.
    public var body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = [:]
        self.body = body
        for (name, value) in headers {
            self.headers[name.lowercased()] = value
        }
    }

    /// Returns the value of the given header, matched case-insensitively.
    public func value(forHeader name: String) -> String? {
        headers[name.lowercased()]
    }
}

/// The HTTP layer an ``IpregistryClient`` sends its requests through.
///
/// The default implementation is ``URLSessionTransport``. Provide your own
/// conformance to route requests through a different HTTP stack (for example
/// AsyncHTTPClient on server-side Swift) or to stub responses in tests.
///
/// Conformances should throw `CancellationError` when the surrounding task is
/// cancelled, and any other error for a transport-level failure. Transport
/// errors are subject to the client's retry policy; HTTP error statuses must
/// be returned as a normal ``HTTPTransportResponse``, not thrown.
public protocol HTTPTransport: Sendable {
    /// Executes the request and returns the response, whatever its status
    /// code.
    func execute(_ request: HTTPTransportRequest) async throws -> HTTPTransportResponse
}

/// The default ``HTTPTransport``, backed by a `URLSession`.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    /// Creates a transport with its own ephemeral `URLSession`, which uses no
    /// persistent caches, cookies, or credential storage.
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        self.init(session: URLSession(configuration: configuration))
    }

    /// Creates a transport backed by the given session, giving full control
    /// over connection pooling, proxying, TLS, and instrumentation. The caller
    /// retains ownership of the session.
    public init(session: URLSession) {
        self.session = session
    }

    public func execute(_ request: HTTPTransportRequest) async throws -> HTTPTransportResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = request.timeout
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        // A continuation-based bridge is used instead of URLSession's async
        // methods because the latter are not uniformly available across Apple
        // platforms and swift-corelibs-foundation.
        let box = DataTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: urlRequest) { data, response, error in
                    if let error {
                        if (error as? URLError)?.code == .cancelled {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(throwing: error)
                        }
                        return
                    }
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                        return
                    }
                    var headers: [String: String] = [:]
                    for (name, value) in httpResponse.allHeaderFields {
                        headers[String(describing: name)] = String(describing: value)
                    }
                    continuation.resume(
                        returning: HTTPTransportResponse(
                            statusCode: httpResponse.statusCode,
                            headers: headers,
                            body: data ?? Data()
                        )
                    )
                }
                box.store(task)
                task.resume()
            }
        } onCancel: {
            box.cancel()
        }
    }
}

/// Holds the in-flight data task so a task cancellation can reach it, closing
/// the race where cancellation lands before the task is stored.
private final class DataTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var isCancelled = false

    func store(_ task: URLSessionDataTask) {
        lock.lock()
        defer { lock.unlock() }
        if isCancelled {
            task.cancel()
        } else {
            self.task = task
        }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        isCancelled = true
        task?.cancel()
    }
}

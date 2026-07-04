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

/// A client for the [Ipregistry](https://ipregistry.co) IP geolocation and
/// threat data API.
///
/// You can obtain an API key, along with a generous free tier, at
/// [ipregistry.co](https://ipregistry.co).
///
/// ```swift
/// let client = IpregistryClient(apiKey: "YOUR_API_KEY")
/// let info = try await client.lookup("8.8.8.8")
/// print(info.location.country.name ?? "unknown")
/// ```
///
/// A client is immutable and safe to share across tasks and actors. By default
/// it performs no caching, retries transient failures up to three times, and
/// times out requests after 15 seconds; customize this behavior with
/// ``Configuration``, and pass an ``InMemoryCache`` to enable caching.
///
/// API-level failures are thrown as ``APIError`` and client-side failures
/// (network, cancellation, decoding) as ``ClientError``.
public final class IpregistryClient: Sendable {
    /// The configuration the client was created with.
    public let configuration: Configuration

    /// The cache used by the client, or `nil` when caching is disabled (the
    /// default).
    public let cache: (any IpregistryCache)?

    private let apiKey: String
    private let transport: any HTTPTransport

    /// Creates a client authenticating with the given API key.
    ///
    /// - Parameters:
    ///   - apiKey: Your Ipregistry API key.
    ///   - configuration: The client settings; see ``Configuration``.
    ///   - cache: A cache for successful lookups. Defaults to `nil` — no
    ///     caching — so data is never stale.
    ///   - transport: The HTTP layer requests are sent through. Defaults to a
    ///     ``URLSessionTransport`` with its own ephemeral `URLSession`.
    public init(
        apiKey: String,
        configuration: Configuration = Configuration(),
        cache: (any IpregistryCache)? = nil,
        transport: (any HTTPTransport)? = nil
    ) {
        self.apiKey = apiKey
        self.configuration = configuration
        self.cache = cache
        self.transport = transport ?? URLSessionTransport()
    }

    // MARK: - Single lookup

    /// Returns the data associated with the given IP address.
    ///
    /// The `ip` argument must be a non-empty IPv4 or IPv6 address; to look up
    /// the requester's own IP, use ``lookupOrigin(options:)`` instead.
    ///
    /// When a cache is configured, a hit is returned without contacting the
    /// API.
    ///
    /// - Throws: ``APIError`` when the API reports a failure, ``ClientError``
    ///   for client-side failures.
    public func lookup(_ ip: String, options: LookupOptions = LookupOptions()) async throws -> IPInfo {
        guard !ip.isEmpty else {
            throw ClientError(message: "ip must not be empty; use lookupOrigin(options:) for the requester IP")
        }

        let key = Self.cacheKey(ip: ip, options: options)
        if let cache, let hit = await cache.get(key) {
            return hit
        }

        let data = try await send(request(method: "GET", url: try lookupURL(ip: ip, options: options)))
        let info: IPInfo = try Self.decode(data)
        if let cache {
            await cache.set(key, info)
        }
        return info
    }

    /// Returns the data associated with the IP address the request originates
    /// from, enriched with parsed User-Agent data.
    ///
    /// Origin lookups are never cached, because the requester IP is only known
    /// from the response.
    ///
    /// - Throws: ``APIError`` when the API reports a failure, ``ClientError``
    ///   for client-side failures.
    public func lookupOrigin(options: LookupOptions = LookupOptions()) async throws -> RequesterIPInfo {
        let data = try await send(request(method: "GET", url: try lookupURL(ip: "", options: options)))
        return try Self.decode(data)
    }

    // MARK: - Batch lookup

    /// Resolves several IP addresses in a single request.
    ///
    /// The returned array preserves the order of `ips`, and each entry may
    /// independently succeed or fail (for example on an invalid address):
    ///
    /// ```swift
    /// for result in try await client.lookupBatch(["8.8.8.8", "1.1.1.1"]) {
    ///     switch result {
    ///     case .success(let info):
    ///         print(info.location.country.name ?? "unknown")
    ///     case .failure(let error):
    ///         print("entry failed: \(error)")
    ///     }
    /// }
    /// ```
    ///
    /// A thrown error indicates the whole request failed (for example
    /// authentication or a network error), not the failure of an individual
    /// entry.
    ///
    /// The Ipregistry API accepts up to
    /// ``Configuration/defaultMaxBatchSize`` addresses per request; larger
    /// arrays are transparently split into chunks dispatched with bounded
    /// concurrency (see ``Configuration/maxBatchSize`` and
    /// ``Configuration/batchConcurrency``) and reassembled in input order.
    /// Entries already present in the cache are served locally; only the
    /// remainder are requested from the API, and freshly resolved entries are
    /// cached.
    ///
    /// - Throws: ``APIError`` when the API reports a whole-request failure,
    ///   ``ClientError`` for client-side failures.
    public func lookupBatch(
        _ ips: [String],
        options: LookupOptions = LookupOptions()
    ) async throws -> [Result<IPInfo, APIError>] {
        var cached = [IPInfo?](repeating: nil, count: ips.count)
        var misses: [String] = []
        if let cache {
            for (index, ip) in ips.enumerated() {
                if let hit = await cache.get(Self.cacheKey(ip: ip, options: options)) {
                    cached[index] = hit
                } else {
                    misses.append(ip)
                }
            }
        } else {
            misses = ips
        }

        let fresh = try await resolveMisses(misses, options: options)

        var results: [Result<IPInfo, APIError>] = []
        results.reserveCapacity(ips.count)
        var nextFresh = 0
        for index in ips.indices {
            if let hit = cached[index] {
                results.append(.success(hit))
                continue
            }
            guard nextFresh < fresh.count else {
                // Defensive: the API returned fewer results than requested.
                results.append(.failure(APIError(message: "missing result for requested IP address")))
                continue
            }
            let result = fresh[nextFresh]
            nextFresh += 1
            results.append(result)
            if case .success(let info) = result, let cache {
                await cache.set(Self.cacheKey(ip: ips[index], options: options), info)
            }
        }
        return results
    }

    // MARK: - User-Agent parsing

    /// Parses one or more raw User-Agent strings (such as the `User-Agent`
    /// header of an incoming HTTP request) into structured data.
    ///
    /// Results preserve the order of the input, and each entry may
    /// independently succeed or fail.
    ///
    /// - Throws: ``APIError`` when the API reports a whole-request failure,
    ///   ``ClientError`` for client-side failures.
    public func parseUserAgents(_ userAgents: [String]) async throws -> [Result<UserAgent, APIError>] {
        let body: Data
        do {
            body = try JSONEncoder().encode(userAgents)
        } catch {
            throw ClientError(message: "failed to encode request body", underlyingError: error)
        }

        let data = try await send(request(method: "POST", url: try userAgentURL(), body: body))
        let envelope: ResultsEnvelope<UserAgent> = try Self.decode(data)
        return envelope.results
    }

    /// Variadic convenience over `parseUserAgents(_:)` taking an array.
    public func parseUserAgents(_ userAgents: String...) async throws -> [Result<UserAgent, APIError>] {
        try await parseUserAgents(userAgents)
    }

    // MARK: - Cache keys

    /// Returns the cache key the client uses for the given IP address and
    /// options, so entries can be invalidated on a custom cache:
    ///
    /// ```swift
    /// await cache.invalidate(IpregistryClient.cacheKey(ip: "8.8.8.8"))
    /// ```
    ///
    /// The key is deterministic regardless of how the options were populated.
    public static func cacheKey(ip: String, options: LookupOptions = LookupOptions()) -> String {
        let query = options.canonicalQuery
        return query.isEmpty ? ip : "\(ip);\(query)"
    }

    // MARK: - Request plumbing

    private func resolveMisses(
        _ misses: [String],
        options: LookupOptions
    ) async throws -> [Result<IPInfo, APIError>] {
        if misses.isEmpty {
            return []
        }
        if misses.count <= configuration.maxBatchSize {
            return try await performBatchRequest(misses, options: options)
        }
        return try await resolveChunks(misses, options: options)
    }

    /// Splits `misses` into API-sized chunks, dispatches them with at most
    /// ``Configuration/batchConcurrency`` in flight, and concatenates their
    /// results in order. If any chunk fails, the first error is thrown and the
    /// remaining in-flight requests are cancelled.
    private func resolveChunks(
        _ misses: [String],
        options: LookupOptions
    ) async throws -> [Result<IPInfo, APIError>] {
        let size = configuration.maxBatchSize
        var chunks: [[String]] = []
        var start = 0
        while start < misses.count {
            let end = min(start + size, misses.count)
            chunks.append(Array(misses[start..<end]))
            start = end
        }

        var chunkResults = [[Result<IPInfo, APIError>]?](repeating: nil, count: chunks.count)
        try await withThrowingTaskGroup(of: (Int, [Result<IPInfo, APIError>]).self) { group in
            var next = 0
            while next < min(configuration.batchConcurrency, chunks.count) {
                let index = next
                let chunk = chunks[index]
                group.addTask {
                    (index, try await self.performBatchRequest(chunk, options: options))
                }
                next += 1
            }
            while let (index, results) = try await group.next() {
                chunkResults[index] = results
                if next < chunks.count {
                    let nextIndex = next
                    let chunk = chunks[nextIndex]
                    group.addTask {
                        (nextIndex, try await self.performBatchRequest(chunk, options: options))
                    }
                    next += 1
                }
            }
        }
        return chunkResults.compactMap { $0 }.flatMap { $0 }
    }

    /// Performs a single POST batch request for the given addresses.
    private func performBatchRequest(
        _ ips: [String],
        options: LookupOptions
    ) async throws -> [Result<IPInfo, APIError>] {
        let body: Data
        do {
            body = try JSONEncoder().encode(ips)
        } catch {
            throw ClientError(message: "failed to encode request body", underlyingError: error)
        }

        let data = try await send(request(method: "POST", url: try lookupURL(ip: "", options: options), body: body))
        let envelope: ResultsEnvelope<IPInfo> = try Self.decode(data)
        return envelope.results
    }

    private func request(method: String, url: URL, body: Data? = nil) -> HTTPTransportRequest {
        var headers = [
            "Authorization": "ApiKey \(apiKey)",
            "User-Agent": configuration.userAgent,
            "Accept": "application/json",
        ]
        if body != nil {
            headers["Content-Type"] = "application/json"
        }
        return HTTPTransportRequest(
            method: method,
            url: url,
            headers: headers,
            body: body,
            timeout: configuration.timeout
        )
    }

    /// Performs a request with automatic retries and returns the raw 2xx
    /// response body. Non-2xx responses are converted to ``APIError``,
    /// transport failures to ``ClientError``.
    private func send(_ request: HTTPTransportRequest) async throws -> Data {
        var attempt = 0
        while true {
            let response: HTTPTransportResponse
            do {
                response = try await transport.execute(request)
            } catch let error as CancellationError {
                throw ClientError(message: "request cancelled", underlyingError: error)
            } catch {
                if Task.isCancelled {
                    throw ClientError(message: "request cancelled", underlyingError: error)
                }
                // Transport errors are retried up to maxRetries regardless of
                // the retry-on-status flags, matching the other official
                // Ipregistry client libraries.
                if attempt < configuration.maxRetries {
                    try await backoff(attempt: attempt)
                    attempt += 1
                    continue
                }
                throw ClientError(message: "request failed", underlyingError: error)
            }

            if (200..<300).contains(response.statusCode) {
                return response.body
            }

            if shouldRetry(status: response.statusCode), attempt < configuration.maxRetries {
                try await backoff(attempt: attempt, retryAfter: Self.retryAfterSeconds(response))
                attempt += 1
                continue
            }

            throw Self.parseAPIError(body: response.body, status: response.statusCode)
        }
    }

    private func shouldRetry(status: Int) -> Bool {
        if status == 429 {
            return configuration.retryOnTooManyRequests
        }
        if (500..<600).contains(status) {
            return configuration.retryOnServerError
        }
        return false
    }

    /// Waits before the next retry attempt, honoring an explicit `Retry-After`
    /// duration when positive and otherwise using exponential backoff.
    private func backoff(attempt: Int, retryAfter: TimeInterval = 0) async throws {
        var delay = retryAfter
        if delay <= 0 {
            delay = configuration.retryInterval * pow(2, Double(min(attempt, 30)))
        }
        // Cap the delay at 24 hours so the nanosecond conversion cannot
        // overflow with extreme configuration values.
        delay = min(delay, 86_400)
        do {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        } catch {
            throw ClientError(message: "request cancelled during retry backoff", underlyingError: error)
        }
    }

    // MARK: - URLs, decoding, and error parsing

    /// Builds the request URL for a single-IP or origin lookup. An empty `ip`
    /// targets the origin (requester) endpoint.
    private func lookupURL(ip: String, options: LookupOptions) throws -> URL {
        try buildURL(pathComponent: ip, queryItems: options.queryItems)
    }

    private func userAgentURL() throws -> URL {
        try buildURL(pathComponent: "user_agent", queryItems: [])
    }

    /// The characters allowed unescaped in the IP path segment. `:` is safe
    /// there — the segment never starts the path — and keeping it unescaped
    /// preserves IPv6 addresses as-is.
    private static let pathSegmentAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.insert(charactersIn: ":")
        return allowed
    }()

    private func buildURL(pathComponent: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: true) else {
            throw ClientError(message: "invalid base URL: \(configuration.baseURL)")
        }
        var path = components.percentEncodedPath
        while path.hasSuffix("/") {
            path.removeLast()
        }
        let encoded =
            pathComponent.addingPercentEncoding(withAllowedCharacters: Self.pathSegmentAllowed) ?? pathComponent
        components.percentEncodedPath = "\(path)/\(encoded)"
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw ClientError(message: "failed to build request URL for: \(pathComponent)")
        }
        return url
    }

    /// Decodes a successful response body.
    private static func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ClientError(message: "failed to decode response", underlyingError: error)
        }
    }

    /// Converts a non-2xx response body into an ``APIError``, falling back to
    /// a generic message when the body is not a recognizable error payload.
    private static func parseAPIError(body: Data, status: Int) -> APIError {
        if let payload = try? JSONDecoder().decode(APIErrorPayload.self, from: body),
            let code = payload.code, !code.isEmpty
        {
            return payload.apiError
        }
        return APIError(message: "unexpected HTTP status \(status)")
    }

    /// Parses a `Retry-After` header expressed as an integer number of
    /// seconds. Returns 0 when the header is absent or not a valid
    /// non-negative integer (the HTTP-date form is not supported, matching the
    /// other official Ipregistry client libraries).
    static func retryAfterSeconds(_ response: HTTPTransportResponse) -> TimeInterval {
        guard let value = response.value(forHeader: "Retry-After"),
            let seconds = Int64(value.trimmingCharacters(in: .whitespaces)),
            seconds >= 0
        else {
            return 0
        }
        return TimeInterval(seconds)
    }
}

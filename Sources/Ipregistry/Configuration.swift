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

extension IpregistryClient {
    /// The settings that customize an ``IpregistryClient``.
    ///
    /// The default configuration targets the public Ipregistry API with a
    /// 15-second per-request timeout, retries transient failures up to three
    /// times, and splits large batch lookups into chunks of up to 1024
    /// addresses dispatched four at a time.
    ///
    /// ```swift
    /// var configuration = IpregistryClient.Configuration()
    /// configuration.retryOnTooManyRequests = true
    /// let client = IpregistryClient(apiKey: "YOUR_API_KEY", configuration: configuration)
    /// ```
    public struct Configuration: Sendable {
        /// The base URL of the public Ipregistry API,
        /// `https://api.ipregistry.co`.
        public static let defaultBaseURL = URL(string: "https://api.ipregistry.co")!

        /// The maximum number of IP addresses the Ipregistry API accepts in a
        /// single batch request. ``IpregistryClient/lookupBatch(_:options:)``
        /// transparently splits larger arrays into several requests so callers
        /// never have to.
        public static let defaultMaxBatchSize = 1024

        /// The base URL of the Ipregistry API. Override it for testing or to
        /// target a private deployment. A trailing slash is ignored.
        public var baseURL: URL

        /// The per-request timeout, in seconds. Defaults to 15 seconds.
        ///
        /// The timeout is carried on every ``HTTPTransportRequest``; a custom
        /// ``HTTPTransport`` may apply its own policy instead.
        public var timeout: TimeInterval

        /// The maximum number of automatic retries performed in addition to
        /// the initial attempt. Set to 0 to disable retries. Defaults to 3.
        public var maxRetries: Int

        /// The base backoff between retries, in seconds. Successive retries
        /// use an exponentially increasing delay (`retryInterval * 2^attempt`).
        /// When a 429 response carries a `Retry-After` header, that value
        /// takes precedence. Defaults to 1 second.
        public var retryInterval: TimeInterval

        /// Whether 5xx responses and transient network errors are retried.
        /// Defaults to `true`.
        public var retryOnServerError: Bool

        /// Whether *429 Too Many Requests* responses are retried, honoring the
        /// `Retry-After` header when present. Ipregistry does not rate limit
        /// by default (it is opt-in per API key), so this defaults to `false`.
        public var retryOnTooManyRequests: Bool

        /// The maximum number of IP addresses sent in a single batch request.
        /// ``IpregistryClient/lookupBatch(_:options:)`` splits larger arrays
        /// into this many addresses per request. Values are clamped to
        /// 1...``defaultMaxBatchSize`` (the API limit).
        public var maxBatchSize: Int {
            didSet { maxBatchSize = Self.clampBatchSize(maxBatchSize) }
        }

        /// How many batch sub-requests ``IpregistryClient/lookupBatch(_:options:)``
        /// dispatches concurrently when an array is large enough to be split
        /// into chunks. Defaults to 4. Set it to 1 for strictly sequential
        /// dispatch, which is gentler on a rate-limited API key. Values below
        /// 1 are clamped to 1.
        public var batchConcurrency: Int {
            didSet { batchConcurrency = max(1, batchConcurrency) }
        }

        /// The value of the `User-Agent` header sent with every request.
        public var userAgent: String

        /// Creates a configuration.
        ///
        /// All parameters default to the values documented on the
        /// corresponding property.
        public init(
            baseURL: URL = Configuration.defaultBaseURL,
            timeout: TimeInterval = 15,
            maxRetries: Int = 3,
            retryInterval: TimeInterval = 1,
            retryOnServerError: Bool = true,
            retryOnTooManyRequests: Bool = false,
            maxBatchSize: Int = Configuration.defaultMaxBatchSize,
            batchConcurrency: Int = 4,
            userAgent: String = IpregistryClient.defaultUserAgent
        ) {
            self.baseURL = baseURL
            self.timeout = timeout
            self.maxRetries = max(0, maxRetries)
            self.retryInterval = retryInterval > 0 ? retryInterval : 1
            self.retryOnServerError = retryOnServerError
            self.retryOnTooManyRequests = retryOnTooManyRequests
            self.maxBatchSize = Self.clampBatchSize(maxBatchSize)
            self.batchConcurrency = max(1, batchConcurrency)
            self.userAgent = userAgent
        }

        private static func clampBatchSize(_ value: Int) -> Int {
            min(max(1, value), defaultMaxBatchSize)
        }
    }
}

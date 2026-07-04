[<img src="https://cdn.ipregistry.co/icons/favicon-96x96.png" alt="Ipregistry" width="64"/>](https://ipregistry.co/)
# Ipregistry Swift Client Library

[![License](http://img.shields.io/:license-apache-blue.svg)](LICENSE)
[![Swift CI](https://github.com/ipregistry/ipregistry-swift/actions/workflows/swift.yml/badge.svg)](https://github.com/ipregistry/ipregistry-swift/actions/workflows/swift.yml)
[![Lint](https://github.com/ipregistry/ipregistry-swift/actions/workflows/lint.yml/badge.svg)](https://github.com/ipregistry/ipregistry-swift/actions/workflows/lint.yml)
[![Swift Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fipregistry%2Fipregistry-swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ipregistry/ipregistry-swift)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fipregistry%2Fipregistry-swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ipregistry/ipregistry-swift)

This is the official Swift client library for the [Ipregistry](https://ipregistry.co) IP geolocation and threat data
API, allowing you to look up your own IP address or specified ones. Responses return multiple data points including
carrier, company, currency, location, time zone, threat information, and more. The library can also parse raw
User-Agent strings.

The library has **zero external dependencies** — it is built entirely on the Swift standard library and Foundation —
and is fully `async/await` based, `Sendable`, and compiled in the Swift 6 language mode.

## Getting Started

You'll need an Ipregistry API key, which you can get along with 100,000 free lookups by signing up for a free account
at [https://ipregistry.co](https://ipregistry.co).

### Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ipregistry/ipregistry-swift.git", from: "1.0.0")
]
```

and add `"Ipregistry"` to your target dependencies. In Xcode, use *File > Add Package Dependencies…* with the
repository URL.

Requires Swift 6.0+ (Xcode 16+). Supported platforms: macOS 12+, iOS 15+, tvOS 15+, watchOS 8+, visionOS 1+, and
Linux.

### Quick start

#### Single IP lookup

```swift
import Ipregistry

let client = IpregistryClient(apiKey: "YOUR_API_KEY")

// Look up data for a given IPv4 or IPv6 address.
// On the server side, retrieve the client IP from the request headers.
let info = try await client.lookup("54.85.132.205")
print(info.location.country.name ?? "unknown")
```

#### Origin IP lookup

To look up the IP address the request is sent from — no argument needed — use `lookupOrigin`. It returns a
`RequesterIPInfo`, which additionally carries parsed User-Agent data:

```swift
let origin = try await client.lookupOrigin()
print(origin.ip ?? "-", origin.location.country.name ?? "-")
print(origin.userAgent?.name ?? "-")
```

#### Batch IP lookup

`lookupBatch` resolves many IP addresses in a single request. Each entry may independently succeed or fail (for
example on an invalid address), so results are returned as an array of Swift's standard `Result`:

```swift
let results = try await client.lookupBatch(["73.2.2.2", "8.8.8.8", "2001:67c:2e8:22::c100:68b"])

for result in results {
    switch result {
    case .success(let info):
        print(info.location.country.name ?? "unknown")
    case .failure(let error):
        // Handle a per-entry error (e.g. invalid IP address).
        print("entry failed: \(error)")
    }
}
```

The Ipregistry API accepts up to 1024 IP addresses per request. `lookupBatch` transparently splits larger arrays into
several requests, dispatched with bounded concurrency, and reassembles the results in input order — so you can pass an
arbitrarily long array without hitting `TOO_MANY_IPS`. Tune the behavior when needed:

```swift
var configuration = IpregistryClient.Configuration()
configuration.maxBatchSize = 1024      // addresses per request (max/default: 1024)
configuration.batchConcurrency = 4     // concurrent sub-requests (default: 4; 1 = sequential)
let client = IpregistryClient(apiKey: "YOUR_API_KEY", configuration: configuration)
```

Only cache misses are sent to the API; if a whole sub-request fails (network or API error), `lookupBatch` throws that
error, whereas an individual bad address surfaces as a per-entry `Result.failure` as shown above.

### Typed IP addresses

IP addresses are passed as strings, which is how they usually arrive (for example from a request's `X-Forwarded-For`
header). On Apple platforms, if you already hold a parsed `Network.IPv4Address` or `Network.IPv6Address`, typed
convenience overloads are available:

```swift
import Network

let address = IPv4Address("8.8.8.8")!
let info = try await client.lookup(address)
```

## Options

Lookups accept options that map to Ipregistry query parameters:

```swift
let info = try await client.lookup(
    "8.8.8.8",
    options: LookupOptions(
        fields: "location.country.name,security",  // select only these fields
        hostname: true                             // resolve reverse-DNS hostname
    )
)
```

| Option              | Description                                                                                                                 |
|---------------------|-----------------------------------------------------------------------------------------------------------------------------|
| `hostname`          | Enable reverse-DNS hostname resolution (disabled by default).                                                              |
| `fields`            | Restrict the response to the given [fields](https://ipregistry.co/docs/filtering-selecting-fields), reducing payload size. |
| `parameters`        | Arbitrary query parameters not covered by a dedicated property.                                                            |

## Caching

Although the client has built-in support for in-memory caching, it is **disabled by default** to ensure data freshness.

To enable caching, pass an `InMemoryCache` when constructing the client:

```swift
let client = IpregistryClient(apiKey: "YOUR_API_KEY", cache: InMemoryCache())
```

The in-memory cache is an actor and supports size- and time-based eviction (LRU with a TTL):

```swift
let cache = InMemoryCache(
    maxSize: 8192,     // maximum number of entries (default 4096)
    timeToLive: 600    // entry lifetime in seconds (default 10 minutes)
)

let client = IpregistryClient(apiKey: "YOUR_API_KEY", cache: cache)
```

Origin (requester) lookups are never cached, because the requester IP is only known from the response. Batch lookups
transparently serve already-cached entries and only request the remainder from the API.

You can provide your own cache implementation by conforming to the `IpregistryCache` protocol:

```swift
public protocol IpregistryCache: Sendable {
    func get(_ key: String) async -> IPInfo?
    func set(_ key: String, _ value: IPInfo) async
    func invalidate(_ key: String) async
    func invalidateAll() async
}
```

## Retries

Failed requests are automatically retried with an exponential backoff. By default, up to 3 retries are performed on
transient network errors and 5xx server responses.

Because Ipregistry does not rate limit by default (rate limiting is opt-in per API key), retries on
_429 Too Many Requests_ responses are **disabled by default**. Enable them if your API key is configured with a rate
limit and you want the client to wait and retry (honoring the `Retry-After` header when present):

```swift
var configuration = IpregistryClient.Configuration()
configuration.maxRetries = 3                  // 0 disables retries entirely
configuration.retryInterval = 1               // base backoff in seconds (interval * 2^attempt)
configuration.retryOnServerError = true       // retry on 5xx (default: true)
configuration.retryOnTooManyRequests = true   // retry on 429 (default: false)
```

## Concurrency, cancellation, and transport

Every method is `async` and cooperates with Swift's structured concurrency: cancelling the surrounding task cancels
the in-flight request (and any retry backoff). An `IpregistryClient` is immutable and `Sendable`, so share one
instance across tasks and actors.

```swift
let task = Task {
    try await client.lookup("8.8.8.8")
}
// Later:
task.cancel()
```

By default the client sends requests through its own ephemeral `URLSession` with a 15-second per-request timeout
(adjust it with `configuration.timeout`). For full control over connection pooling, proxying, TLS, or
instrumentation, supply your own session:

```swift
let session = URLSession(configuration: .default)
let client = IpregistryClient(apiKey: "YOUR_API_KEY", transport: URLSessionTransport(session: session))
```

To route requests through an entirely different HTTP stack (for example AsyncHTTPClient on server-side Swift), or to
stub responses in tests, conform to the small `HTTPTransport` protocol and pass your implementation as `transport:`.

## Errors

The library throws two typed error kinds:

- **`APIError`** — the API reported a failure (e.g. insufficient credits, throttling, invalid input). It carries a
  typed `code` (which preserves unrecognized raw codes), a `message`, and a `resolution`.
- **`ClientError`** — a client-side failure (network error, request cancellation, response decoding). The underlying
  cause is available as `underlyingError`.

```swift
do {
    let info = try await client.lookup("8.8.8.8")
} catch let error as APIError where error.code == .insufficientCredits {
    // handle exhausted credits
} catch let error as APIError where error.code == .tooManyRequests {
    // handle rate limiting
} catch let error as APIError {
    // other API failure
} catch let error as ClientError {
    // handle network / decoding error
}
```

The full list of error codes is documented at [ipregistry.co/docs/errors](https://ipregistry.co/docs/errors).

## Parsing User-Agents

Parse one or more raw User-Agent strings (such as the `User-Agent` header of an incoming request) into structured
data:

```swift
let results = try await client.parseUserAgents("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/120.0")
let userAgent = try results[0].get()
print(userAgent.name ?? "-", userAgent.operatingSystem.name ?? "-")
```

## Filtering bots

You might want to prevent Ipregistry API calls for crawlers or bots browsing your pages. To help identify bots from
the User-Agent, the library includes a lightweight helper:

```swift
// For testing you can retrieve your current User-Agent from:
// https://api.ipregistry.co/user_agent?key=YOUR_API_KEY (look at the "user_agent" field)
if !UserAgent.isBot(userAgentFromRequestHeader) {
    let info = try await client.lookup(clientIP)
    // ...
}
```

## Examples

Runnable examples live in the [`Examples/`](Examples) directory as a standalone package; set your key and run one:

```bash
cd Examples
IPREGISTRY_API_KEY=YOUR_API_KEY swift run single
IPREGISTRY_API_KEY=YOUR_API_KEY swift run origin
IPREGISTRY_API_KEY=YOUR_API_KEY swift run batch
```

## Testing

The library ships with two tiers of tests, both written with Swift Testing:

- **Unit / behavior tests** run offline against an in-memory transport — no API key or network is required. This is
  the default `swift test` and what CI runs on Linux and macOS.
- **System tests** exercise the live Ipregistry API. They are skipped unless `IPREGISTRY_API_KEY` is set (each
  successful lookup consumes credits):

  ```bash
  IPREGISTRY_API_KEY=YOUR_API_KEY swift test --filter IpregistrySystemTests
  ```

## Other Libraries

There are official Ipregistry client libraries available for many languages including
[Java](https://github.com/ipregistry/ipregistry-java),
[Javascript](https://github.com/ipregistry/ipregistry-javascript),
[Python](https://github.com/ipregistry/ipregistry-python),
[Go](https://github.com/ipregistry/ipregistry-go) and more.

Are you looking for an official client with a programming language or framework we do not support yet?
[Let us know](mailto:support@ipregistry.co).

## License

This library is released under the [Apache 2.0 license](LICENSE).

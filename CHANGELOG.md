# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-07-04

### Added

- Initial release of the official Ipregistry Swift client library.
- Single IP lookup (`lookup`), origin lookup (`lookupOrigin`), and batch lookup (`lookupBatch`) with transparent
  chunking of arrays larger than the API limit, dispatched with bounded concurrency.
- User-Agent parsing (`parseUserAgents`) and the `UserAgent.isBot` helper.
- Typed `Network.IPAddress` lookup overloads on Apple platforms.
- Automatic retries with exponential backoff on transient network errors and 5xx responses, with opt-in retry on 429
  honoring `Retry-After`.
- Opt-in caching through the `IpregistryCache` protocol and the built-in `InMemoryCache` actor (LRU with TTL).
- Pluggable `HTTPTransport` protocol with a `URLSession`-backed default, enabling offline testing and custom HTTP
  stacks.
- Typed errors: `APIError` (with typed, forward-compatible `ErrorCode`) and `ClientError`.
- Swift 6 language mode, `Sendable` throughout, zero external dependencies. Supports macOS 12+, iOS 15+, tvOS 15+,
  watchOS 8+, visionOS 1+, and Linux.

[Unreleased]: https://github.com/ipregistry/ipregistry-swift/compare/1.0.0...HEAD
[1.0.0]: https://github.com/ipregistry/ipregistry-swift/releases/tag/1.0.0

# Contributing

Thanks for your interest in improving the official Ipregistry Swift client.

## Development

The library targets Swift 6.0+ and has **no external dependencies** — please keep it that way (standard library and
Foundation only).

Common tasks:

```bash
swift build                                        # build the library
swift test                                         # run the offline test suite
swift format lint --strict --recursive Sources Tests Examples Package.swift   # lint
swift format --in-place --recursive Sources Tests Examples Package.swift      # format
IPREGISTRY_API_KEY=... swift test --filter IpregistrySystemTests              # live system tests
```

On Linux without a local toolchain, everything runs in the official container:

```bash
docker run --rm -v "$PWD":/src -w /src swift:6.3 swift test
```

Before opening a pull request, please make sure `swift test` passes and the code is `swift format` clean.

## Guidelines

- **Public API stability.** This package is `1.x`; avoid breaking changes to public declarations. If a breaking change
  is unavoidable, it must go through a new major version.
- **Concurrency.** The package compiles in the Swift 6 language mode with strict concurrency; keep every public type
  `Sendable` and avoid `@unchecked Sendable` unless a lock demonstrably guards the state.
- **Errors.** Surface API failures as `APIError` and client-side failures as `ClientError`; carry underlying causes in
  `ClientError.underlyingError`.
- **Tests.** Add or update tests for any behavior change. Offline behavior is tested with the in-memory
  `MockTransport`; no live API key is required. Live system tests live in `Tests/IpregistrySystemTests` and run
  against the real API when `IPREGISTRY_API_KEY` is set; they consume credits, so keep them minimal.
- **Docs.** Keep the `README.md`, DocC comments, and runnable examples in `Examples/` in sync with the code.
- **Changelog.** Record notable changes in `CHANGELOG.md` under `[Unreleased]`.

## Releasing

Releases are cut with the *Release* GitHub Actions workflow, which validates the version against
`Sources/Ipregistry/Version.swift` and `CHANGELOG.md`, runs the full test gate (including live system tests), then
creates the tag and GitHub release. Tagging is what publishes the package: Swift Package Manager resolves versions
from git tags directly.

## Reporting issues

For bugs or feature requests, please open a GitHub issue. For account or API questions, contact
[support@ipregistry.co](mailto:support@ipregistry.co).

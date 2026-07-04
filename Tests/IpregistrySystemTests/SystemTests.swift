import Foundation
import Ipregistry
import Testing

/// System tests exercise the live Ipregistry API and consume credits. They
/// only run when the `IPREGISTRY_API_KEY` environment variable is set, and are
/// skipped cleanly otherwise:
///
/// ```bash
/// IPREGISTRY_API_KEY=YOUR_API_KEY swift test --filter IpregistrySystemTests
/// ```
private let apiKey = ProcessInfo.processInfo.environment["IPREGISTRY_API_KEY"]

@Suite("System tests (live API)", .enabled(if: apiKey != nil))
struct SystemTests {
    private var client: IpregistryClient {
        IpregistryClient(apiKey: apiKey ?? "")
    }

    @Test func lookupKnownIP() async throws {
        let info = try await client.lookup("8.8.8.8")

        #expect(info.ip == "8.8.8.8")
        #expect(info.type == .ipv4)
        #expect(info.location.country.code == "US")
        #expect(info.connection.asn != nil)
        #expect(info.timeZone.id != nil)
        #expect(info.currency.code != nil)
    }

    @Test func lookupWithFieldsFilter() async throws {
        let info = try await client.lookup(
            "8.8.8.8",
            options: LookupOptions(fields: "location.country.name")
        )

        #expect(info.location.country.name == "United States")
        // Everything outside the selection is absent and falls back to
        // defaults instead of failing to decode.
        #expect(info.ip == nil)
        #expect(info.connection.asn == nil)
    }

    @Test func lookupWithHostnameResolution() async throws {
        let info = try await client.lookup("8.8.8.8", options: LookupOptions(hostname: true))

        #expect(info.hostname != nil)
    }

    @Test func lookupIPv6() async throws {
        let info = try await client.lookup("2001:4860:4860::8888")

        #expect(info.type == .ipv6)
        #expect(info.location.country.code != nil)
    }

    @Test func lookupOrigin() async throws {
        let origin = try await client.lookupOrigin()

        #expect(origin.ip?.isEmpty == false)
        #expect(origin.location.country.code != nil)
    }

    @Test func lookupBatchWithPerEntryError() async throws {
        let results = try await client.lookupBatch(["8.8.8.8", "not-an-ip", "1.1.1.1"])

        #expect(results.count == 3)
        #expect(try results[0].get().location.country.code == "US")
        #expect(try results[2].get().ip == "1.1.1.1")
        guard case .failure(let error) = results[1] else {
            Issue.record("expected a per-entry error for the invalid address")
            return
        }
        #expect(error.code == .invalidIPAddress)
    }

    @Test func parseUserAgents() async throws {
        let results = try await client.parseUserAgents(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) "
                + "Chrome/120.0.0.0 Safari/537.36"
        )

        #expect(results.count == 1)
        let userAgent = try results[0].get()
        #expect(userAgent.name == "Chrome")
        #expect(userAgent.operatingSystem.name != nil)
    }

    @Test func invalidAPIKeyIsReported() async throws {
        let invalidClient = IpregistryClient(apiKey: "invalid-key-for-tests")

        do {
            _ = try await invalidClient.lookup("8.8.8.8")
            Issue.record("expected an APIError")
        } catch let error as APIError {
            #expect(error.code == .invalidAPIKey || error.code == .disabledAPIKey)
        }
    }
}

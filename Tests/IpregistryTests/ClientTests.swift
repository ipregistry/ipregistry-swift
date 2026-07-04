import Foundation
import Testing

@testable import Ipregistry

@Suite("Client requests and responses")
struct ClientTests {
    @Test func lookupSendsExpectedRequestAndDecodes() async throws {
        let transport = MockTransport(json: Fixtures.googleDNS)
        let client = makeClient(transport: transport)

        let info = try await client.lookup("8.8.8.8")

        #expect(info.ip == "8.8.8.8")
        #expect(info.type == .ipv4)
        #expect(info.hostname == "dns.google")
        #expect(info.location.country.name == "United States")
        #expect(info.connection.asn == 15169)
        #expect(info.security.isCloudProvider)
        #expect(!info.security.isVPN)
        #expect(info.timeZone.id == "America/Los_Angeles")
        #expect(info.timeZone.offset == -25200)
        #expect(info.currency.format.negative.prefix == "-$")

        let request = try #require(await transport.requests.first)
        #expect(request.method == "GET")
        #expect(request.url.absoluteString == "https://api.ipregistry.co/8.8.8.8")
        #expect(request.headers["Authorization"] == "ApiKey test-key")
        #expect(request.headers["User-Agent"] == IpregistryClient.defaultUserAgent)
        #expect(request.headers["Accept"] == "application/json")
        #expect(request.body == nil)
    }

    @Test func lookupWithEmptyIPThrowsWithoutContactingAPI() async throws {
        let transport = MockTransport(json: Fixtures.googleDNS)
        let client = makeClient(transport: transport)

        await #expect(throws: ClientError.self) {
            try await client.lookup("")
        }
        #expect(await transport.requestCount == 0)
    }

    @Test func lookupAppendsOptionsAsSortedQueryParameters() async throws {
        let transport = MockTransport(json: Fixtures.googleDNS)
        let client = makeClient(transport: transport)

        let options = LookupOptions(
            fields: "location.country.name,security",
            hostname: true,
            parameters: ["pretty": "true"]
        )
        _ = try await client.lookup("8.8.8.8", options: options)

        let request = try #require(await transport.requests.first)
        #expect(
            request.url.absoluteString
                == "https://api.ipregistry.co/8.8.8.8?fields=location.country.name,security&hostname=true&pretty=true"
        )
    }

    @Test func lookupOriginTargetsRootAndParsesUserAgent() async throws {
        let transport = MockTransport(json: Fixtures.originLookup)
        let client = makeClient(transport: transport)

        let origin = try await client.lookupOrigin()

        #expect(origin.ip == "203.0.113.10")
        #expect(origin.location.country.code == "FR")
        #expect(origin.userAgent?.name == "Chrome")
        #expect(origin.userAgent?.operatingSystem.name == "macOS")

        let request = try #require(await transport.requests.first)
        #expect(request.url.absoluteString == "https://api.ipregistry.co/")
    }

    @Test func lookupBatchPostsIPsAndMapsPerEntryResults() async throws {
        let transport = MockTransport(
            json: """
                {
                  "results": [
                    {"ip": "8.8.8.8", "type": "IPv4"},
                    {"code": "INVALID_IP_ADDRESS", "message": "Invalid IP", "resolution": "Fix it."},
                    {"ip": "1.1.1.1", "type": "IPv4"}
                  ]
                }
                """
        )
        let client = makeClient(transport: transport)

        let results = try await client.lookupBatch(["8.8.8.8", "not-an-ip", "1.1.1.1"])

        #expect(results.count == 3)
        #expect(try results[0].get().ip == "8.8.8.8")
        #expect(try results[2].get().ip == "1.1.1.1")
        guard case .failure(let error) = results[1] else {
            Issue.record("expected a per-entry failure")
            return
        }
        #expect(error.code == .invalidIPAddress)
        #expect(error.message == "Invalid IP")
        #expect(error.resolution == "Fix it.")

        let request = try #require(await transport.requests.first)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://api.ipregistry.co/")
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(try requestedIPs(request) == ["8.8.8.8", "not-an-ip", "1.1.1.1"])
    }

    @Test func lookupBatchWithEmptyInputSkipsAPI() async throws {
        let transport = MockTransport(json: "{}")
        let client = makeClient(transport: transport)

        let results = try await client.lookupBatch([])

        #expect(results.isEmpty)
        #expect(await transport.requestCount == 0)
    }

    @Test func lookupBatchFillsMissingResultsDefensively() async throws {
        let transport = MockTransport(json: #"{"results": [{"ip": "8.8.8.8"}]}"#)
        let client = makeClient(transport: transport)

        let results = try await client.lookupBatch(["8.8.8.8", "1.1.1.1"])

        #expect(results.count == 2)
        #expect(try results[0].get().ip == "8.8.8.8")
        guard case .failure(let error) = results[1] else {
            Issue.record("expected a defensive failure for the missing entry")
            return
        }
        #expect(error.message == "missing result for requested IP address")
    }

    @Test func parseUserAgentsPostsToUserAgentEndpoint() async throws {
        let transport = MockTransport(
            json: """
                {
                  "results": [
                    {"header": "Mozilla/5.0", "name": "Chrome", "os": {"name": "macOS"}},
                    {"code": "BAD_REQUEST", "message": "Unparseable."}
                  ]
                }
                """
        )
        let client = makeClient(transport: transport)

        let results = try await client.parseUserAgents("Mozilla/5.0", "garbage")

        #expect(results.count == 2)
        #expect(try results[0].get().name == "Chrome")
        #expect(try results[0].get().operatingSystem.name == "macOS")
        guard case .failure(let error) = results[1] else {
            Issue.record("expected a per-entry failure")
            return
        }
        #expect(error.code == .badRequest)

        let request = try #require(await transport.requests.first)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://api.ipregistry.co/user_agent")
        #expect(try requestedIPs(request) == ["Mozilla/5.0", "garbage"])
    }

    @Test func parseUserAgentsWithNoArgumentsSendsEmptyArray() async throws {
        let transport = MockTransport(json: #"{"results": []}"#)
        let client = makeClient(transport: transport)

        let results = try await client.parseUserAgents()

        #expect(results.isEmpty)
        let request = try #require(await transport.requests.first)
        #expect(request.body.map { String(decoding: $0, as: UTF8.self) } == "[]")
    }

    @Test func apiErrorCarriesCodeMessageAndResolution() async throws {
        let transport = MockTransport(status: 402, json: Fixtures.insufficientCredits)
        let client = makeClient(transport: transport)

        do {
            _ = try await client.lookup("8.8.8.8")
            Issue.record("expected an APIError")
        } catch let error as APIError {
            #expect(error.code == .insufficientCredits)
            #expect(error.message == "You have exhausted your credits.")
            #expect(error.resolution == "Purchase credits or wait for your quota to renew.")
            #expect(
                error.description
                    == "ipregistry: You have exhausted your credits. (INSUFFICIENT_CREDITS): "
                    + "Purchase credits or wait for your quota to renew."
            )
        }
    }

    @Test func nonJSONErrorBodyFallsBackToGenericAPIError() async throws {
        let transport = MockTransport(status: 502, json: "<html>Bad Gateway</html>")
        let client = makeClient(transport: transport) { $0.retryOnServerError = false }

        do {
            _ = try await client.lookup("8.8.8.8")
            Issue.record("expected an APIError")
        } catch let error as APIError {
            #expect(error.code == nil)
            #expect(error.message == "unexpected HTTP status 502")
        }
    }

    @Test func undecodableSuccessBodyThrowsClientError() async throws {
        let transport = MockTransport(json: "not json at all")
        let client = makeClient(transport: transport)

        do {
            _ = try await client.lookup("8.8.8.8")
            Issue.record("expected a ClientError")
        } catch let error as ClientError {
            #expect(error.message == "failed to decode response")
            #expect(error.underlyingError is DecodingError)
        }
    }

    @Test func customUserAgentIsSent() async throws {
        let transport = MockTransport(json: Fixtures.googleDNS)
        let client = makeClient(transport: transport) { $0.userAgent = "MyApp/2.0" }

        _ = try await client.lookup("8.8.8.8")

        let request = try #require(await transport.requests.first)
        #expect(request.headers["User-Agent"] == "MyApp/2.0")
    }

    @Test func baseURLTrailingSlashAndIPv6PathAreHandled() async throws {
        let transport = MockTransport(json: Fixtures.googleDNS)
        let client = makeClient(transport: transport) {
            $0.baseURL = URL(string: "https://example.com/proxy/")!
        }

        _ = try await client.lookup("2001:67c:2e8:22::c100:68b")

        let request = try #require(await transport.requests.first)
        #expect(request.url.absoluteString == "https://example.com/proxy/2001:67c:2e8:22::c100:68b")
    }
}

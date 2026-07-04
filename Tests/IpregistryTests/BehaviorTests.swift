import Foundation
import Testing

@testable import Ipregistry

@Suite("Retries, caching, and batch chunking")
struct BehaviorTests {
    // MARK: - Retries

    @Test func serverErrorIsRetriedThenSucceeds() async throws {
        let transport = MockTransport { _, index in
            index == 0
                ? jsonResponse(status: 500, #"{"code": "INTERNAL", "message": "boom"}"#)
                : jsonResponse(Fixtures.googleDNS)
        }
        let client = makeClient(transport: transport)

        let info = try await client.lookup("8.8.8.8")

        #expect(info.ip == "8.8.8.8")
        #expect(await transport.requestCount == 2)
    }

    @Test func transportErrorIsRetriedThenSucceeds() async throws {
        let transport = MockTransport { _, index in
            if index == 0 {
                throw URLError(.networkConnectionLost)
            }
            return jsonResponse(Fixtures.googleDNS)
        }
        let client = makeClient(transport: transport)

        let info = try await client.lookup("8.8.8.8")

        #expect(info.ip == "8.8.8.8")
        #expect(await transport.requestCount == 2)
    }

    @Test func exhaustedRetriesSurfaceClientError() async throws {
        let transport = MockTransport { _, _ in
            throw URLError(.networkConnectionLost)
        }
        let client = makeClient(transport: transport) { $0.maxRetries = 2 }

        do {
            _ = try await client.lookup("8.8.8.8")
            Issue.record("expected a ClientError")
        } catch let error as ClientError {
            #expect(error.message == "request failed")
            #expect((error.underlyingError as? URLError)?.code == .networkConnectionLost)
        }
        #expect(await transport.requestCount == 3)
    }

    @Test func serverErrorIsNotRetriedWhenDisabled() async throws {
        let transport = MockTransport(status: 500, json: #"{"code": "INTERNAL", "message": "boom"}"#)
        let client = makeClient(transport: transport) { $0.retryOnServerError = false }

        do {
            _ = try await client.lookup("8.8.8.8")
            Issue.record("expected an APIError")
        } catch let error as APIError {
            #expect(error.code == .internalError)
        }
        #expect(await transport.requestCount == 1)
    }

    @Test func tooManyRequestsIsNotRetriedByDefault() async throws {
        let transport = MockTransport(
            status: 429,
            json: #"{"code": "TOO_MANY_REQUESTS", "message": "slow down"}"#
        )
        let client = makeClient(transport: transport)

        do {
            _ = try await client.lookup("8.8.8.8")
            Issue.record("expected an APIError")
        } catch let error as APIError {
            #expect(error.code == .tooManyRequests)
        }
        #expect(await transport.requestCount == 1)
    }

    @Test func tooManyRequestsIsRetriedWhenEnabledHonoringRetryAfter() async throws {
        let transport = MockTransport { _, index in
            index == 0
                ? jsonResponse(
                    status: 429,
                    #"{"code": "TOO_MANY_REQUESTS", "message": "slow down"}"#,
                    headers: ["Retry-After": "0"]
                )
                : jsonResponse(Fixtures.googleDNS)
        }
        let client = makeClient(transport: transport) { $0.retryOnTooManyRequests = true }

        let info = try await client.lookup("8.8.8.8")

        #expect(info.ip == "8.8.8.8")
        #expect(await transport.requestCount == 2)
    }

    @Test func cancellationSurfacesAsClientError() async throws {
        let transport = MockTransport { _, _ in
            try await Task.sleep(nanoseconds: 10_000_000_000)
            return jsonResponse(Fixtures.googleDNS)
        }
        let client = makeClient(transport: transport)

        let task = Task {
            try await client.lookup("8.8.8.8")
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("expected a ClientError")
        } catch let error as ClientError {
            #expect(error.message.contains("cancelled"))
        }
    }

    // MARK: - Caching

    @Test func repeatLookupsAreServedFromCache() async throws {
        let transport = MockTransport(json: Fixtures.googleDNS)
        let client = makeClient(transport: transport, cache: InMemoryCache())

        let first = try await client.lookup("8.8.8.8")
        let second = try await client.lookup("8.8.8.8")

        #expect(first == second)
        #expect(await transport.requestCount == 1)
    }

    @Test func lookupsWithDifferentOptionsAreCachedSeparately() async throws {
        let transport = MockTransport(json: Fixtures.googleDNS)
        let client = makeClient(transport: transport, cache: InMemoryCache())

        _ = try await client.lookup("8.8.8.8")
        _ = try await client.lookup("8.8.8.8", options: LookupOptions(hostname: true))

        #expect(await transport.requestCount == 2)
    }

    @Test func originLookupsAreNeverCached() async throws {
        let transport = MockTransport(json: Fixtures.originLookup)
        let client = makeClient(transport: transport, cache: InMemoryCache())

        _ = try await client.lookupOrigin()
        _ = try await client.lookupOrigin()

        #expect(await transport.requestCount == 2)
    }

    @Test func fullyCachedBatchSkipsAPI() async throws {
        let transport = MockTransport { request, _ in
            batchEcho(try requestedIPs(request))
        }
        let client = makeClient(transport: transport, cache: InMemoryCache())

        _ = try await client.lookupBatch(["8.8.8.8", "1.1.1.1"])
        #expect(await transport.requestCount == 1)

        let results = try await client.lookupBatch(["1.1.1.1", "8.8.8.8"])
        #expect(await transport.requestCount == 1)
        #expect(try results.map { try $0.get().ip } == ["1.1.1.1", "8.8.8.8"])
    }

    @Test func partiallyCachedBatchOnlyRequestsMisses() async throws {
        let transport = MockTransport { request, _ in
            request.method == "GET"
                ? jsonResponse(Fixtures.googleDNS)
                : batchEcho(try requestedIPs(request))
        }
        let client = makeClient(transport: transport, cache: InMemoryCache())

        _ = try await client.lookup("8.8.8.8")
        let results = try await client.lookupBatch(["1.1.1.1", "8.8.8.8", "9.9.9.9"])

        #expect(try results.map { try $0.get().ip } == ["1.1.1.1", "8.8.8.8", "9.9.9.9"])
        #expect(await transport.requestCount == 2)
        let batchRequest = try #require(await transport.requests.last)
        #expect(try requestedIPs(batchRequest) == ["1.1.1.1", "9.9.9.9"])
    }

    @Test func batchResolvedEntriesAreCachedForSingleLookups() async throws {
        let transport = MockTransport { request, _ in
            batchEcho(try requestedIPs(request))
        }
        let client = makeClient(transport: transport, cache: InMemoryCache())

        _ = try await client.lookupBatch(["8.8.8.8"])
        let info = try await client.lookup("8.8.8.8")

        #expect(info.ip == "8.8.8.8")
        #expect(await transport.requestCount == 1)
    }

    // MARK: - Batch chunking

    @Test func largeBatchIsChunkedAndReassembledInOrder() async throws {
        let transport = MockTransport { request, _ in
            batchEcho(try requestedIPs(request))
        }
        let client = makeClient(transport: transport) { $0.maxBatchSize = 2 }

        let ips = (1...5).map { "10.0.0.\($0)" }
        let results = try await client.lookupBatch(ips)

        #expect(try results.map { try $0.get().ip } == ips)
        #expect(await transport.requestCount == 3)

        let sizes = try await transport.requests.map { try requestedIPs($0).count }.sorted()
        #expect(sizes == [1, 2, 2])
    }

    @Test func sequentialChunkingPreservesDispatchOrder() async throws {
        let transport = MockTransport { request, _ in
            batchEcho(try requestedIPs(request))
        }
        let client = makeClient(transport: transport) {
            $0.maxBatchSize = 2
            $0.batchConcurrency = 1
        }

        let ips = (1...6).map { "10.0.0.\($0)" }
        let results = try await client.lookupBatch(ips)

        #expect(try results.map { try $0.get().ip } == ips)
        let bodies = try await transport.requests.map { try requestedIPs($0) }
        #expect(bodies == [["10.0.0.1", "10.0.0.2"], ["10.0.0.3", "10.0.0.4"], ["10.0.0.5", "10.0.0.6"]])
    }

    @Test func failingChunkFailsTheWholeBatch() async throws {
        let transport = MockTransport { request, _ in
            let ips = try requestedIPs(request)
            if ips.contains("10.0.0.3") {
                return jsonResponse(status: 403, #"{"code": "FORBIDDEN_IP", "message": "denied"}"#)
            }
            return batchEcho(ips)
        }
        let client = makeClient(transport: transport) {
            $0.maxBatchSize = 2
            $0.batchConcurrency = 1
        }

        do {
            _ = try await client.lookupBatch((1...6).map { "10.0.0.\($0)" })
            Issue.record("expected an APIError")
        } catch let error as APIError {
            #expect(error.code == .forbiddenIP)
        }
    }
}

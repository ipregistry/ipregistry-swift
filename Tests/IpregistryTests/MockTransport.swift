import Foundation

@testable import Ipregistry

/// An in-memory ``HTTPTransport`` that records every request and answers with
/// a programmable handler, so the whole client behavior is testable offline.
actor MockTransport: HTTPTransport {
    typealias Handler = @Sendable (HTTPTransportRequest, Int) async throws -> HTTPTransportResponse

    private let handler: Handler
    private(set) var requests: [HTTPTransportRequest] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    /// A transport that always answers with the same response.
    init(status: Int = 200, json: String, headers: [String: String] = [:]) {
        self.init { _, _ in
            HTTPTransportResponse(statusCode: status, headers: headers, body: Data(json.utf8))
        }
    }

    func execute(_ request: HTTPTransportRequest) async throws -> HTTPTransportResponse {
        requests.append(request)
        return try await handler(request, requests.count - 1)
    }

    var requestCount: Int {
        requests.count
    }
}

func jsonResponse(status: Int = 200, _ json: String, headers: [String: String] = [:]) -> HTTPTransportResponse {
    HTTPTransportResponse(statusCode: status, headers: headers, body: Data(json.utf8))
}

/// Decodes the IP addresses of a batch request body.
func requestedIPs(_ request: HTTPTransportRequest) throws -> [String] {
    try JSONDecoder().decode([String].self, from: request.body ?? Data())
}

/// Builds a batch response echoing the requested IP addresses.
func batchEcho(_ ips: [String]) -> HTTPTransportResponse {
    let entries = ips.map { #"{"ip": "\#($0)"}"# }.joined(separator: ",")
    return jsonResponse(#"{"results": [\#(entries)]}"#)
}

/// A client wired to the given transport with fast retries.
func makeClient(
    transport: MockTransport,
    cache: (any IpregistryCache)? = nil,
    configure: (inout IpregistryClient.Configuration) -> Void = { _ in }
) -> IpregistryClient {
    var configuration = IpregistryClient.Configuration()
    configuration.retryInterval = 0.001
    configure(&configuration)
    return IpregistryClient(apiKey: "test-key", configuration: configuration, cache: cache, transport: transport)
}

enum Fixtures {
    /// A realistic single-lookup payload, abridged from the Ipregistry docs.
    static let googleDNS = """
        {
          "ip": "8.8.8.8",
          "type": "IPv4",
          "hostname": "dns.google",
          "carrier": {"name": null, "mcc": null, "mnc": null},
          "company": {"domain": "google.com", "name": "Google LLC", "type": "business"},
          "connection": {
            "asn": 15169,
            "domain": "google.com",
            "organization": "Google LLC",
            "route": "8.8.8.0/24",
            "type": "business"
          },
          "currency": {
            "code": "USD",
            "name": "US Dollar",
            "name_native": "US Dollar",
            "plural": "US dollars",
            "plural_native": "US dollars",
            "symbol": "$",
            "symbol_native": "$",
            "format": {
              "decimal_separator": ".",
              "group_separator": ",",
              "negative": {"prefix": "-$", "suffix": ""},
              "positive": {"prefix": "$", "suffix": ""}
            }
          },
          "location": {
            "continent": {"code": "NA", "name": "North America"},
            "country": {
              "area": 9629091,
              "borders": ["CA", "MX"],
              "calling_code": "1",
              "capital": "Washington D.C.",
              "code": "US",
              "name": "United States",
              "population": 331002651,
              "population_density": 34.37,
              "flag": {
                "emoji": "🇺🇸",
                "emoji_unicode": "U+1F1FA U+1F1F8",
                "emojitwo": "https://cdn.ipregistry.co/flags/emojitwo/us.svg",
                "noto": "https://cdn.ipregistry.co/flags/noto/us.png",
                "twemoji": "https://cdn.ipregistry.co/flags/twemoji/us.svg",
                "wikimedia": "https://cdn.ipregistry.co/flags/wikimedia/us.svg"
              },
              "languages": [{"code": "en", "name": "English", "native": "English"}],
              "tld": ".us"
            },
            "region": {"code": "US-CA", "name": "California"},
            "city": "Mountain View",
            "postal": "94043",
            "latitude": 37.40599,
            "longitude": -122.078514,
            "language": {"code": "en", "name": "English", "native": "English"},
            "in_eu": false
          },
          "security": {
            "is_abuser": false,
            "is_attacker": false,
            "is_bogon": false,
            "is_cloud_provider": true,
            "is_proxy": false,
            "is_relay": false,
            "is_tor": false,
            "is_tor_exit": false,
            "is_anonymous": false,
            "is_threat": false,
            "is_vpn": false
          },
          "time_zone": {
            "id": "America/Los_Angeles",
            "abbreviation": "PDT",
            "current_time": "2024-05-06T09:23:00-07:00",
            "name": "Pacific Daylight Time",
            "offset": -25200,
            "in_daylight_saving": true
          }
        }
        """

    static let originLookup = """
        {
          "ip": "203.0.113.10",
          "type": "IPv4",
          "location": {"country": {"code": "FR", "name": "France"}},
          "user_agent": {
            "header": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/120.0",
            "name": "Chrome",
            "type": "browser",
            "version": "120.0",
            "version_major": "120",
            "device": {"brand": "Apple", "name": "Mac", "type": "desktop"},
            "engine": {"name": "Blink", "type": "browser", "version": "120.0", "version_major": "120"},
            "os": {"name": "macOS", "type": "desktop", "version": "10.15.7"}
          }
        }
        """

    static let insufficientCredits = """
        {
          "code": "INSUFFICIENT_CREDITS",
          "message": "You have exhausted your credits.",
          "resolution": "Purchase credits or wait for your quota to renew."
        }
        """
}

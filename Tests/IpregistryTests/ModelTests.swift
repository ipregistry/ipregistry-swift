import Foundation
import Testing

@testable import Ipregistry

@Suite("Model decoding")
struct ModelTests {
    @Test func fullPayloadDecodes() throws {
        let info = try JSONDecoder().decode(IPInfo.self, from: Data(Fixtures.googleDNS.utf8))

        #expect(info.company.name == "Google LLC")
        #expect(info.company.type == .business)
        #expect(info.connection.route == "8.8.8.0/24")
        #expect(info.connection.type == .business)
        #expect(info.currency.code == "USD")
        #expect(info.currency.symbol == "$")
        #expect(info.location.continent.code == "NA")
        #expect(info.location.country.code == "US")
        #expect(info.location.country.borders == ["CA", "MX"])
        #expect(info.location.country.population == 331_002_651)
        #expect(info.location.country.flag.emoji == "🇺🇸")
        #expect(info.location.country.languages.first?.code == "en")
        #expect(info.location.country.tld == ".us")
        #expect(info.location.region.name == "California")
        #expect(info.location.city == "Mountain View")
        #expect(info.location.latitude == 37.40599)
        #expect(info.location.longitude == -122.078514)
        #expect(!info.location.inEU)
        #expect(info.timeZone.inDaylightSaving)
        #expect(info.carrier.name == nil)
    }

    @Test func minimalPayloadFallsBackToDefaults() throws {
        let info = try JSONDecoder().decode(IPInfo.self, from: Data(#"{"ip": "1.1.1.1"}"#.utf8))

        #expect(info.ip == "1.1.1.1")
        #expect(info.type == nil)
        #expect(info.hostname == nil)
        #expect(info.location.country.name == nil)
        #expect(info.location.country.area == 0)
        #expect(info.location.country.borders.isEmpty)
        #expect(info.location.latitude == nil)
        #expect(info.connection.asn == nil)
        #expect(!info.security.isThreat)
        #expect(info.timeZone.offset == 0)
        #expect(info.currency.format.positive.prefix == nil)
    }

    @Test func nullNestedObjectsFallBackToDefaults() throws {
        let json = """
            {
              "ip": "1.1.1.1",
              "carrier": null,
              "company": null,
              "connection": null,
              "currency": null,
              "location": null,
              "security": null,
              "time_zone": null
            }
            """
        let info = try JSONDecoder().decode(IPInfo.self, from: Data(json.utf8))

        #expect(info.ip == "1.1.1.1")
        #expect(info.security == Security())
        #expect(info.location == Location())
    }

    @Test func encodingRoundTripsLosslessly() throws {
        let original = try JSONDecoder().decode(IPInfo.self, from: Data(Fixtures.googleDNS.utf8))
        let reencoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(IPInfo.self, from: reencoded)

        #expect(decoded == original)
    }

    @Test func requesterInfoRoundTripsAndForwardsMembers() throws {
        let origin = try JSONDecoder().decode(RequesterIPInfo.self, from: Data(Fixtures.originLookup.utf8))

        // Dynamic member lookup forwards IPInfo properties.
        #expect(origin.ip == "203.0.113.10")
        #expect(origin.location.country.name == "France")
        #expect(origin.userAgent?.engine.name == "Blink")
        #expect(origin.userAgent?.device.brand == "Apple")

        let reencoded = try JSONEncoder().encode(origin)
        let decoded = try JSONDecoder().decode(RequesterIPInfo.self, from: reencoded)
        #expect(decoded == origin)
    }

    @Test func unknownTypedValuesArePreserved() throws {
        let json = """
            {
              "ip": "1.1.1.1",
              "type": "IPv10",
              "company": {"type": "space-agency"},
              "connection": {"type": "satellite"}
            }
            """
        let info = try JSONDecoder().decode(IPInfo.self, from: Data(json.utf8))

        #expect(info.type == IPType(rawValue: "IPv10"))
        #expect(info.company.type == CompanyType(rawValue: "space-agency"))
        #expect(info.connection.type == ConnectionType(rawValue: "satellite"))
    }

    @Test func batchEnvelopeSplitsSuccessesAndErrors() throws {
        let json = """
            {
              "results": [
                {"ip": "8.8.8.8"},
                {"code": "RESERVED_IP_ADDRESS", "message": "Reserved.", "resolution": "Use a public IP."},
                {"ip": "1.1.1.1"}
              ]
            }
            """
        let envelope = try JSONDecoder().decode(ResultsEnvelope<IPInfo>.self, from: Data(json.utf8))

        #expect(envelope.results.count == 3)
        #expect(try envelope.results[0].get().ip == "8.8.8.8")
        guard case .failure(let error) = envelope.results[1] else {
            Issue.record("expected a failure entry")
            return
        }
        #expect(error.code == .reservedIPAddress)
        #expect(error.resolution == "Use a public IP.")
    }

    @Test func batchEnvelopeTreatsNullCodeAsSuccess() throws {
        let json = #"{"results": [{"ip": "8.8.8.8", "code": null}]}"#
        let envelope = try JSONDecoder().decode(ResultsEnvelope<IPInfo>.self, from: Data(json.utf8))

        #expect(try envelope.results[0].get().ip == "8.8.8.8")
    }

    @Test func modelsCanBeBuiltAsFixtures() {
        let info = IPInfo(
            ip: "8.8.8.8",
            type: .ipv4,
            location: Location(country: Country(code: "US", name: "United States")),
            security: Security(isVPN: true)
        )

        #expect(info.location.country.code == "US")
        #expect(info.security.isVPN)
        #expect(info.carrier == Carrier())
    }
}

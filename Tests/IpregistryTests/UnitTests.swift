import Foundation
import Testing

@testable import Ipregistry

@Suite("Units")
struct UnitTests {
    @Test(
        "isBot heuristic",
        arguments: [
            ("Googlebot/2.1 (+http://www.google.com/bot.html)", true),
            ("Mozilla/5.0 (compatible; bingbot/2.0)", true),
            ("Baiduspider+(+http://www.baidu.com/search/spider.htm)", true),
            ("Mozilla/5.0 (compatible; Yahoo! Slurp)", true),
            ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/120.0", false),
            ("curl/8.0.1", false),
            ("", false),
        ]
    )
    func isBot(userAgent: String, expected: Bool) {
        #expect(UserAgent.isBot(userAgent) == expected)
    }

    @Test func errorCodeConstantsMatchRawValues() {
        #expect(ErrorCode.insufficientCredits.rawValue == "INSUFFICIENT_CREDITS")
        #expect(ErrorCode.internalError.rawValue == "INTERNAL")
        #expect(ErrorCode(rawValue: "SOMETHING_NEW").rawValue == "SOMETHING_NEW")
        #expect(ErrorCode(rawValue: "TOO_MANY_REQUESTS") == .tooManyRequests)
    }

    @Test func cacheKeyIsDeterministicAcrossOptionPopulation() {
        let viaProperties = LookupOptions(fields: "security", hostname: true)
        var viaParameters = LookupOptions()
        viaParameters.parameters = ["hostname": "true", "fields": "security"]

        let first = IpregistryClient.cacheKey(ip: "8.8.8.8", options: viaProperties)
        let second = IpregistryClient.cacheKey(ip: "8.8.8.8", options: viaParameters)

        #expect(first == second)
        #expect(first == "8.8.8.8;fields=security&hostname=true")
        #expect(IpregistryClient.cacheKey(ip: "8.8.8.8") == "8.8.8.8")
    }

    @Test func dedicatedOptionPropertiesWinOverRawParameters() {
        let options = LookupOptions(
            fields: "security",
            hostname: false,
            parameters: ["fields": "shadowed", "hostname": "true"]
        )

        let items = Dictionary(uniqueKeysWithValues: options.queryItems.map { ($0.name, $0.value ?? "") })
        #expect(items == ["fields": "security", "hostname": "false"])
    }

    @Test(
        "Retry-After parsing",
        arguments: [
            ("3", 3.0),
            ("0", 0.0),
            (" 7 ", 7.0),
            ("-1", 0.0),
            ("soon", 0.0),
            ("", 0.0),
        ]
    )
    func retryAfterParsing(value: String, expected: TimeInterval) {
        let response = HTTPTransportResponse(statusCode: 429, headers: ["Retry-After": value])
        #expect(IpregistryClient.retryAfterSeconds(response) == expected)
    }

    @Test func retryAfterIsAbsentByDefault() {
        let response = HTTPTransportResponse(statusCode: 429)
        #expect(IpregistryClient.retryAfterSeconds(response) == 0)
    }

    @Test func transportResponseHeaderLookupIsCaseInsensitive() {
        let response = HTTPTransportResponse(statusCode: 200, headers: ["ReTry-AfTer": "5"])
        #expect(response.value(forHeader: "retry-after") == "5")
        #expect(response.value(forHeader: "RETRY-AFTER") == "5")
    }

    @Test func configurationClampsOutOfRangeValues() {
        var configuration = IpregistryClient.Configuration(
            maxRetries: -1,
            retryInterval: -2,
            maxBatchSize: 4096,
            batchConcurrency: 0
        )
        #expect(configuration.maxRetries == 0)
        #expect(configuration.retryInterval == 1)
        #expect(configuration.maxBatchSize == IpregistryClient.Configuration.defaultMaxBatchSize)
        #expect(configuration.batchConcurrency == 1)

        configuration.maxBatchSize = 0
        configuration.batchConcurrency = -3
        #expect(configuration.maxBatchSize == 1)
        #expect(configuration.batchConcurrency == 1)
    }

    @Test func clientErrorDescriptionsIncludeCause() {
        let bare = ClientError(message: "request failed")
        #expect(bare.description == "ipregistry: request failed")

        let withCause = ClientError(message: "request failed", underlyingError: URLError(.timedOut))
        #expect(withCause.description.hasPrefix("ipregistry: request failed: "))
    }

    @Test func apiErrorDescriptionOmitsEmptyParts() {
        #expect(APIError().description == "ipregistry: API error")
        #expect(APIError(code: .badRequest).description == "ipregistry: API error (BAD_REQUEST)")
        #expect(APIError(message: "nope").description == "ipregistry: nope")
    }
}

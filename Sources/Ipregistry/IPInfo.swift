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

/// The version of an IP address.
///
/// `IPType` wraps the raw string returned by the API, so values introduced
/// after this library was released are preserved. Compare against the provided
/// constants: ``ipv4``, ``ipv6``, and ``unknown``.
public struct IPType: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static let ipv4 = IPType(rawValue: "IPv4")
    public static let ipv6 = IPType(rawValue: "IPv6")
    public static let unknown = IPType(rawValue: "Unknown")
}

/// The comprehensive set of information associated with an IP address returned
/// by the Ipregistry API.
///
/// Nested objects (``carrier``, ``company``, ``connection``, ``currency``,
/// ``location``, ``security``, and ``timeZone``) are always present as values,
/// so drilling into them reads naturally even when the API omitted them — for
/// example with ``LookupOptions/fields`` filtering. Absent leaf fields are
/// `nil` (strings and typed values) or hold a zero value (numbers and
/// booleans), matching the API's semantics.
public struct IPInfo: Codable, Hashable, Sendable {
    /// The IP address the data refers to.
    public let ip: String?

    /// The IP version (``IPType/ipv4``, ``IPType/ipv6``, or
    /// ``IPType/unknown``).
    public let type: IPType?

    /// The reverse-DNS hostname, when hostname resolution is requested (see
    /// ``LookupOptions/hostname``) and available.
    public let hostname: String?

    /// Mobile carrier information, when the IP address belongs to one.
    public let carrier: Carrier

    /// Ownership information for the IP address.
    public let company: Company

    /// Network connection information for the IP address.
    public let connection: Connection

    /// Currency information for the IP address location.
    public let currency: Currency

    /// The geographical location associated with the IP address.
    public let location: Location

    /// Threat-intelligence flags for the IP address.
    public let security: Security

    /// Time zone information for the IP address location.
    public let timeZone: TimeZoneInfo

    /// Creates an `IPInfo`. Mostly useful for building fixtures when testing
    /// code that consumes this library.
    public init(
        ip: String? = nil,
        type: IPType? = nil,
        hostname: String? = nil,
        carrier: Carrier = Carrier(),
        company: Company = Company(),
        connection: Connection = Connection(),
        currency: Currency = Currency(),
        location: Location = Location(),
        security: Security = Security(),
        timeZone: TimeZoneInfo = TimeZoneInfo()
    ) {
        self.ip = ip
        self.type = type
        self.hostname = hostname
        self.carrier = carrier
        self.company = company
        self.connection = connection
        self.currency = currency
        self.location = location
        self.security = security
        self.timeZone = timeZone
    }

    private enum CodingKeys: String, CodingKey {
        case ip
        case type
        case hostname
        case carrier
        case company
        case connection
        case currency
        case location
        case security
        case timeZone = "time_zone"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ip = try container.decodeIfPresent(String.self, forKey: .ip)
        type = try container.decodeIfPresent(IPType.self, forKey: .type)
        hostname = try container.decodeIfPresent(String.self, forKey: .hostname)
        carrier = try container.decodeIfPresent(Carrier.self, forKey: .carrier) ?? Carrier()
        company = try container.decodeIfPresent(Company.self, forKey: .company) ?? Company()
        connection = try container.decodeIfPresent(Connection.self, forKey: .connection) ?? Connection()
        currency = try container.decodeIfPresent(Currency.self, forKey: .currency) ?? Currency()
        location = try container.decodeIfPresent(Location.self, forKey: .location) ?? Location()
        security = try container.decodeIfPresent(Security.self, forKey: .security) ?? Security()
        timeZone = try container.decodeIfPresent(TimeZoneInfo.self, forKey: .timeZone) ?? TimeZoneInfo()
    }
}

/// The information returned by ``IpregistryClient/lookupOrigin(options:)``:
/// the requester's ``IPInfo`` enriched with parsed User-Agent data.
///
/// `RequesterIPInfo` forwards ``IPInfo`` properties through dynamic member
/// lookup, so `origin.location.country.name` reads the same as on a plain
/// lookup result.
@dynamicMemberLookup
public struct RequesterIPInfo: Codable, Hashable, Sendable {
    /// The information associated with the requester IP address.
    public let info: IPInfo

    /// The parsed User-Agent of the requester, or `nil` when the API did not
    /// return any.
    public let userAgent: UserAgent?

    /// Creates a `RequesterIPInfo`. Mostly useful for building fixtures when
    /// testing code that consumes this library.
    public init(info: IPInfo = IPInfo(), userAgent: UserAgent? = nil) {
        self.info = info
        self.userAgent = userAgent
    }

    /// Forwards ``IPInfo`` properties, so `origin.ip` and
    /// `origin.location.country.name` work directly.
    public subscript<T>(dynamicMember keyPath: KeyPath<IPInfo, T>) -> T {
        info[keyPath: keyPath]
    }

    private enum CodingKeys: String, CodingKey {
        case userAgent = "user_agent"
    }

    public init(from decoder: any Decoder) throws {
        info = try IPInfo(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userAgent = try container.decodeIfPresent(UserAgent.self, forKey: .userAgent)
    }

    public func encode(to encoder: any Encoder) throws {
        try info.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(userAgent, forKey: .userAgent)
    }
}

/// Mobile carrier information associated with an IP address.
public struct Carrier: Codable, Hashable, Sendable {
    /// The carrier name.
    public let name: String?

    /// The Mobile Country Code.
    public let mcc: String?

    /// The Mobile Network Code.
    public let mnc: String?

    public init(name: String? = nil, mcc: String? = nil, mnc: String? = nil) {
        self.name = name
        self.mcc = mcc
        self.mnc = mnc
    }
}

/// The kind of company that owns an IP address.
///
/// `CompanyType` wraps the raw string returned by the API. Compare against the
/// provided constants.
public struct CompanyType: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static let business = CompanyType(rawValue: "business")
    public static let education = CompanyType(rawValue: "education")
    public static let government = CompanyType(rawValue: "government")
    public static let hosting = CompanyType(rawValue: "hosting")
    public static let isp = CompanyType(rawValue: "isp")
}

/// Ownership information for an IP address.
public struct Company: Codable, Hashable, Sendable {
    public let name: String?
    public let domain: String?
    public let type: CompanyType?

    public init(name: String? = nil, domain: String? = nil, type: CompanyType? = nil) {
        self.name = name
        self.domain = domain
        self.type = type
    }
}

/// The kind of network an IP address belongs to.
///
/// `ConnectionType` wraps the raw string returned by the API. Compare against
/// the provided constants.
public struct ConnectionType: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static let business = ConnectionType(rawValue: "business")
    public static let education = ConnectionType(rawValue: "education")
    public static let government = ConnectionType(rawValue: "government")
    public static let hosting = ConnectionType(rawValue: "hosting")
    public static let inactive = ConnectionType(rawValue: "inactive")
    public static let isp = ConnectionType(rawValue: "isp")
}

/// Network connection information for an IP address.
public struct Connection: Codable, Hashable, Sendable {
    /// The Autonomous System Number, or `nil` when unknown.
    public let asn: Int64?
    public let domain: String?
    public let organization: String?
    public let route: String?
    public let type: ConnectionType?

    public init(
        asn: Int64? = nil,
        domain: String? = nil,
        organization: String? = nil,
        route: String? = nil,
        type: ConnectionType? = nil
    ) {
        self.asn = asn
        self.domain = domain
        self.organization = organization
        self.route = route
        self.type = type
    }
}

/// Currency information for an IP address location.
public struct Currency: Codable, Hashable, Sendable {
    public let code: String?
    public let name: String?
    public let nameNative: String?
    public let plural: String?
    public let pluralNative: String?
    public let symbol: String?
    public let symbolNative: String?
    public let format: CurrencyFormat

    public init(
        code: String? = nil,
        name: String? = nil,
        nameNative: String? = nil,
        plural: String? = nil,
        pluralNative: String? = nil,
        symbol: String? = nil,
        symbolNative: String? = nil,
        format: CurrencyFormat = CurrencyFormat()
    ) {
        self.code = code
        self.name = name
        self.nameNative = nameNative
        self.plural = plural
        self.pluralNative = pluralNative
        self.symbol = symbol
        self.symbolNative = symbolNative
        self.format = format
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case name
        case nameNative = "name_native"
        case plural
        case pluralNative = "plural_native"
        case symbol
        case symbolNative = "symbol_native"
        case format
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        nameNative = try container.decodeIfPresent(String.self, forKey: .nameNative)
        plural = try container.decodeIfPresent(String.self, forKey: .plural)
        pluralNative = try container.decodeIfPresent(String.self, forKey: .pluralNative)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        symbolNative = try container.decodeIfPresent(String.self, forKey: .symbolNative)
        format = try container.decodeIfPresent(CurrencyFormat.self, forKey: .format) ?? CurrencyFormat()
    }
}

/// How monetary values are formatted for a currency.
public struct CurrencyFormat: Codable, Hashable, Sendable {
    public let decimalSeparator: String?
    public let groupSeparator: String?
    public let negative: CurrencyFormatAffix
    public let positive: CurrencyFormatAffix

    public init(
        decimalSeparator: String? = nil,
        groupSeparator: String? = nil,
        negative: CurrencyFormatAffix = CurrencyFormatAffix(),
        positive: CurrencyFormatAffix = CurrencyFormatAffix()
    ) {
        self.decimalSeparator = decimalSeparator
        self.groupSeparator = groupSeparator
        self.negative = negative
        self.positive = positive
    }

    private enum CodingKeys: String, CodingKey {
        case decimalSeparator = "decimal_separator"
        case groupSeparator = "group_separator"
        case negative
        case positive
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        decimalSeparator = try container.decodeIfPresent(String.self, forKey: .decimalSeparator)
        groupSeparator = try container.decodeIfPresent(String.self, forKey: .groupSeparator)
        negative = try container.decodeIfPresent(CurrencyFormatAffix.self, forKey: .negative) ?? CurrencyFormatAffix()
        positive = try container.decodeIfPresent(CurrencyFormatAffix.self, forKey: .positive) ?? CurrencyFormatAffix()
    }
}

/// The prefix and suffix applied around a formatted monetary value (for
/// example the currency symbol and a sign).
public struct CurrencyFormatAffix: Codable, Hashable, Sendable {
    public let prefix: String?
    public let suffix: String?

    public init(prefix: String? = nil, suffix: String? = nil) {
        self.prefix = prefix
        self.suffix = suffix
    }
}

/// Threat-intelligence flags for an IP address.
///
/// Flags default to `false` when the API omits them, for example when the
/// response is narrowed with ``LookupOptions/fields``.
public struct Security: Codable, Hashable, Sendable {
    public let isAbuser: Bool
    public let isAttacker: Bool
    public let isBogon: Bool
    public let isCloudProvider: Bool
    public let isProxy: Bool
    public let isRelay: Bool
    public let isTor: Bool
    public let isTorExit: Bool
    public let isAnonymous: Bool
    public let isThreat: Bool
    public let isVPN: Bool

    public init(
        isAbuser: Bool = false,
        isAttacker: Bool = false,
        isBogon: Bool = false,
        isCloudProvider: Bool = false,
        isProxy: Bool = false,
        isRelay: Bool = false,
        isTor: Bool = false,
        isTorExit: Bool = false,
        isAnonymous: Bool = false,
        isThreat: Bool = false,
        isVPN: Bool = false
    ) {
        self.isAbuser = isAbuser
        self.isAttacker = isAttacker
        self.isBogon = isBogon
        self.isCloudProvider = isCloudProvider
        self.isProxy = isProxy
        self.isRelay = isRelay
        self.isTor = isTor
        self.isTorExit = isTorExit
        self.isAnonymous = isAnonymous
        self.isThreat = isThreat
        self.isVPN = isVPN
    }

    private enum CodingKeys: String, CodingKey {
        case isAbuser = "is_abuser"
        case isAttacker = "is_attacker"
        case isBogon = "is_bogon"
        case isCloudProvider = "is_cloud_provider"
        case isProxy = "is_proxy"
        case isRelay = "is_relay"
        case isTor = "is_tor"
        case isTorExit = "is_tor_exit"
        case isAnonymous = "is_anonymous"
        case isThreat = "is_threat"
        case isVPN = "is_vpn"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isAbuser = try container.decodeIfPresent(Bool.self, forKey: .isAbuser) ?? false
        isAttacker = try container.decodeIfPresent(Bool.self, forKey: .isAttacker) ?? false
        isBogon = try container.decodeIfPresent(Bool.self, forKey: .isBogon) ?? false
        isCloudProvider = try container.decodeIfPresent(Bool.self, forKey: .isCloudProvider) ?? false
        isProxy = try container.decodeIfPresent(Bool.self, forKey: .isProxy) ?? false
        isRelay = try container.decodeIfPresent(Bool.self, forKey: .isRelay) ?? false
        isTor = try container.decodeIfPresent(Bool.self, forKey: .isTor) ?? false
        isTorExit = try container.decodeIfPresent(Bool.self, forKey: .isTorExit) ?? false
        isAnonymous = try container.decodeIfPresent(Bool.self, forKey: .isAnonymous) ?? false
        isThreat = try container.decodeIfPresent(Bool.self, forKey: .isThreat) ?? false
        isVPN = try container.decodeIfPresent(Bool.self, forKey: .isVPN) ?? false
    }
}

/// Time zone information for an IP address location.
///
/// Named `TimeZoneInfo` to avoid colliding with Foundation's `TimeZone`.
public struct TimeZoneInfo: Codable, Hashable, Sendable {
    /// The IANA time zone identifier (for example `"America/Los_Angeles"`).
    public let id: String?
    public let abbreviation: String?
    /// The current local time in ISO 8601 format.
    public let currentTime: String?
    public let name: String?
    /// The current offset from UTC, in seconds.
    public let offset: Int
    public let inDaylightSaving: Bool

    public init(
        id: String? = nil,
        abbreviation: String? = nil,
        currentTime: String? = nil,
        name: String? = nil,
        offset: Int = 0,
        inDaylightSaving: Bool = false
    ) {
        self.id = id
        self.abbreviation = abbreviation
        self.currentTime = currentTime
        self.name = name
        self.offset = offset
        self.inDaylightSaving = inDaylightSaving
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case abbreviation
        case currentTime = "current_time"
        case name
        case offset
        case inDaylightSaving = "in_daylight_saving"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        abbreviation = try container.decodeIfPresent(String.self, forKey: .abbreviation)
        currentTime = try container.decodeIfPresent(String.self, forKey: .currentTime)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        offset = try container.decodeIfPresent(Int.self, forKey: .offset) ?? 0
        inDaylightSaving = try container.decodeIfPresent(Bool.self, forKey: .inDaylightSaving) ?? false
    }
}

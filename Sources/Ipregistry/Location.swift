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

/// The geographical location associated with an IP address.
public struct Location: Codable, Hashable, Sendable {
    public let continent: Continent
    public let country: Country
    /// The administrative region (state/province).
    public let region: Region
    public let city: String?
    /// The postal (ZIP) code.
    public let postal: String?
    /// The decimal-degree latitude, or `nil` when unavailable.
    public let latitude: Double?
    /// The decimal-degree longitude, or `nil` when unavailable.
    public let longitude: Double?
    /// The primary language spoken at the location.
    public let language: Language
    /// Whether the location is within a European Union member state.
    public let inEU: Bool

    public init(
        continent: Continent = Continent(),
        country: Country = Country(),
        region: Region = Region(),
        city: String? = nil,
        postal: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        language: Language = Language(),
        inEU: Bool = false
    ) {
        self.continent = continent
        self.country = country
        self.region = region
        self.city = city
        self.postal = postal
        self.latitude = latitude
        self.longitude = longitude
        self.language = language
        self.inEU = inEU
    }

    private enum CodingKeys: String, CodingKey {
        case continent
        case country
        case region
        case city
        case postal
        case latitude
        case longitude
        case language
        case inEU = "in_eu"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        continent = try container.decodeIfPresent(Continent.self, forKey: .continent) ?? Continent()
        country = try container.decodeIfPresent(Country.self, forKey: .country) ?? Country()
        region = try container.decodeIfPresent(Region.self, forKey: .region) ?? Region()
        city = try container.decodeIfPresent(String.self, forKey: .city)
        postal = try container.decodeIfPresent(String.self, forKey: .postal)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        language = try container.decodeIfPresent(Language.self, forKey: .language) ?? Language()
        inEU = try container.decodeIfPresent(Bool.self, forKey: .inEU) ?? false
    }
}

/// Continent-level information for a location.
public struct Continent: Codable, Hashable, Sendable {
    public let code: String?
    public let name: String?

    public init(code: String? = nil, name: String? = nil) {
        self.code = code
        self.name = name
    }
}

/// Country-level information for a location.
public struct Country: Codable, Hashable, Sendable {
    /// The total land area, in square kilometers.
    public let area: Double
    /// The ISO 3166-1 alpha-2 codes of bordering countries.
    public let borders: [String]
    public let callingCode: String?
    public let capital: String?
    /// The ISO 3166-1 alpha-2 country code (for example `"US"`).
    public let code: String?
    public let name: String?
    /// The estimated number of inhabitants.
    public let population: Int
    /// The number of inhabitants per square kilometer.
    public let populationDensity: Double
    public let flag: Flag
    public let languages: [Language]
    /// The country-code top-level domain (for example `".us"`).
    public let tld: String?

    public init(
        area: Double = 0,
        borders: [String] = [],
        callingCode: String? = nil,
        capital: String? = nil,
        code: String? = nil,
        name: String? = nil,
        population: Int = 0,
        populationDensity: Double = 0,
        flag: Flag = Flag(),
        languages: [Language] = [],
        tld: String? = nil
    ) {
        self.area = area
        self.borders = borders
        self.callingCode = callingCode
        self.capital = capital
        self.code = code
        self.name = name
        self.population = population
        self.populationDensity = populationDensity
        self.flag = flag
        self.languages = languages
        self.tld = tld
    }

    private enum CodingKeys: String, CodingKey {
        case area
        case borders
        case callingCode = "calling_code"
        case capital
        case code
        case name
        case population
        case populationDensity = "population_density"
        case flag
        case languages
        case tld
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        area = try container.decodeIfPresent(Double.self, forKey: .area) ?? 0
        borders = try container.decodeIfPresent([String].self, forKey: .borders) ?? []
        callingCode = try container.decodeIfPresent(String.self, forKey: .callingCode)
        capital = try container.decodeIfPresent(String.self, forKey: .capital)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        population = try container.decodeIfPresent(Int.self, forKey: .population) ?? 0
        populationDensity = try container.decodeIfPresent(Double.self, forKey: .populationDensity) ?? 0
        flag = try container.decodeIfPresent(Flag.self, forKey: .flag) ?? Flag()
        languages = try container.decodeIfPresent([Language].self, forKey: .languages) ?? []
        tld = try container.decodeIfPresent(String.self, forKey: .tld)
    }
}

/// Administrative region (state/province) information.
public struct Region: Codable, Hashable, Sendable {
    /// Typically the ISO 3166-2 subdivision code.
    public let code: String?
    public let name: String?

    public init(code: String? = nil, name: String? = nil) {
        self.code = code
        self.name = name
    }
}

/// Language information.
public struct Language: Codable, Hashable, Sendable {
    public let code: String?
    public let name: String?
    /// The language's name in the language itself.
    public let native: String?

    public init(code: String? = nil, name: String? = nil, native: String? = nil) {
        self.code = code
        self.name = name
        self.native = native
    }
}

/// Representations of a country flag across several icon sets.
public struct Flag: Codable, Hashable, Sendable {
    public let emoji: String?
    public let emojiUnicode: String?
    public let emojitwo: String?
    public let noto: String?
    public let twemoji: String?
    public let wikimedia: String?

    public init(
        emoji: String? = nil,
        emojiUnicode: String? = nil,
        emojitwo: String? = nil,
        noto: String? = nil,
        twemoji: String? = nil,
        wikimedia: String? = nil
    ) {
        self.emoji = emoji
        self.emojiUnicode = emojiUnicode
        self.emojitwo = emojitwo
        self.noto = noto
        self.twemoji = twemoji
        self.wikimedia = wikimedia
    }

    private enum CodingKeys: String, CodingKey {
        case emoji
        case emojiUnicode = "emoji_unicode"
        case emojitwo
        case noto
        case twemoji
        case wikimedia
    }
}

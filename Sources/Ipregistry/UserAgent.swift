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

/// The structured data parsed from a raw User-Agent string.
public struct UserAgent: Codable, Hashable, Sendable {
    /// The raw User-Agent string that was parsed.
    public let header: String?
    public let name: String?
    public let type: String?
    public let version: String?
    public let versionMajor: String?
    public let device: UserAgentDevice
    public let engine: UserAgentEngine
    public let operatingSystem: UserAgentOperatingSystem

    /// Creates a `UserAgent`. Mostly useful for building fixtures when testing
    /// code that consumes this library.
    public init(
        header: String? = nil,
        name: String? = nil,
        type: String? = nil,
        version: String? = nil,
        versionMajor: String? = nil,
        device: UserAgentDevice = UserAgentDevice(),
        engine: UserAgentEngine = UserAgentEngine(),
        operatingSystem: UserAgentOperatingSystem = UserAgentOperatingSystem()
    ) {
        self.header = header
        self.name = name
        self.type = type
        self.version = version
        self.versionMajor = versionMajor
        self.device = device
        self.engine = engine
        self.operatingSystem = operatingSystem
    }

    private enum CodingKeys: String, CodingKey {
        case header
        case name
        case type
        case version
        case versionMajor = "version_major"
        case device
        case engine
        case operatingSystem = "os"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        header = try container.decodeIfPresent(String.self, forKey: .header)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        versionMajor = try container.decodeIfPresent(String.self, forKey: .versionMajor)
        device = try container.decodeIfPresent(UserAgentDevice.self, forKey: .device) ?? UserAgentDevice()
        engine = try container.decodeIfPresent(UserAgentEngine.self, forKey: .engine) ?? UserAgentEngine()
        operatingSystem =
            try container.decodeIfPresent(UserAgentOperatingSystem.self, forKey: .operatingSystem)
            ?? UserAgentOperatingSystem()
    }

    /// Returns whether the given raw User-Agent string looks like a crawler or
    /// bot.
    ///
    /// It is a lightweight heuristic — useful for skipping IP lookups on
    /// automated traffic — that matches the substrings `"bot"`, `"spider"`,
    /// and `"slurp"` case-insensitively.
    ///
    /// ```swift
    /// if !UserAgent.isBot(userAgentHeader) {
    ///     let info = try await client.lookup(clientIP)
    /// }
    /// ```
    public static func isBot(_ userAgent: String) -> Bool {
        let lowercased = userAgent.lowercased()
        return lowercased.contains("bot")
            || lowercased.contains("spider")
            || lowercased.contains("slurp")
    }
}

/// The device data parsed from a User-Agent string.
public struct UserAgentDevice: Codable, Hashable, Sendable {
    public let brand: String?
    public let name: String?
    public let type: String?

    public init(brand: String? = nil, name: String? = nil, type: String? = nil) {
        self.brand = brand
        self.name = name
        self.type = type
    }
}

/// The layout-engine data parsed from a User-Agent string.
public struct UserAgentEngine: Codable, Hashable, Sendable {
    public let name: String?
    public let type: String?
    public let version: String?
    public let versionMajor: String?

    public init(name: String? = nil, type: String? = nil, version: String? = nil, versionMajor: String? = nil) {
        self.name = name
        self.type = type
        self.version = version
        self.versionMajor = versionMajor
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case type
        case version
        case versionMajor = "version_major"
    }
}

/// The operating-system data parsed from a User-Agent string.
public struct UserAgentOperatingSystem: Codable, Hashable, Sendable {
    public let name: String?
    public let type: String?
    public let version: String?

    public init(name: String? = nil, type: String? = nil, version: String? = nil) {
        self.name = name
        self.type = type
        self.version = version
    }
}

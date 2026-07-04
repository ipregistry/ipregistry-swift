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

/// Options that customize a single lookup or batch request by setting query
/// parameters.
///
/// ```swift
/// let info = try await client.lookup(
///     "8.8.8.8",
///     options: LookupOptions(fields: "location.country.name,security", hostname: true)
/// )
/// ```
public struct LookupOptions: Hashable, Sendable {
    /// Restricts the response to the given fields, using Ipregistry's field
    /// selector syntax (for example `"location.country.name,security"`). This
    /// reduces payload size and, in some cases, credit usage. See
    /// [Filtering & selecting fields](https://ipregistry.co/docs/filtering-selecting-fields)
    /// for the syntax.
    public var fields: String?

    /// Enables or disables reverse-DNS hostname resolution for the looked-up
    /// IP addresses. The API default is disabled; `nil` leaves the parameter
    /// unset.
    public var hostname: Bool?

    /// Arbitrary query parameters not covered by a dedicated property. When a
    /// key collides with ``fields`` or ``hostname``, the dedicated property
    /// wins.
    public var parameters: [String: String]

    /// Creates lookup options.
    public init(fields: String? = nil, hostname: Bool? = nil, parameters: [String: String] = [:]) {
        self.fields = fields
        self.hostname = hostname
        self.parameters = parameters
    }

    /// The options collapsed into query items, sorted by name so the produced
    /// URLs — and the cache keys derived from them — are deterministic
    /// regardless of how the options were populated.
    var queryItems: [URLQueryItem] {
        var merged = parameters
        if let fields {
            merged["fields"] = fields
        }
        if let hostname {
            merged["hostname"] = hostname ? "true" : "false"
        }
        return merged.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    }

    /// A canonical `name=value&...` rendering of ``queryItems``, used to
    /// derive cache keys.
    var canonicalQuery: String {
        queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
    }
}

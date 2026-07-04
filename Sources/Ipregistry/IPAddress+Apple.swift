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

#if canImport(Network)
    import Network

    extension IpregistryClient {
        /// Returns the data associated with the given typed IP address.
        ///
        /// This is a convenience over ``lookup(_:options:)`` for callers that
        /// already hold a parsed `Network.IPv4Address` or `Network.IPv6Address`.
        /// Most callers receive IP addresses as strings — for example from a
        /// request header — and can use ``lookup(_:options:)`` directly.
        ///
        /// - Note: For scoped IPv6 addresses (for example link-local addresses
        ///   with an interface such as `fe80::1%en0`), the zone is not sent to
        ///   the API.
        public func lookup(
            _ address: any IPAddress,
            options: LookupOptions = LookupOptions()
        ) async throws -> IPInfo {
            try await lookup(Self.string(for: address), options: options)
        }

        /// The typed-address variant of ``lookupBatch(_:options:)``.
        public func lookupBatch(
            _ addresses: [any IPAddress],
            options: LookupOptions = LookupOptions()
        ) async throws -> [Result<IPInfo, APIError>] {
            try await lookupBatch(addresses.map(Self.string(for:)), options: options)
        }

        /// Renders a typed address as the plain string form the API expects,
        /// dropping any IPv6 zone (`%interface`) suffix.
        private static func string(for address: any IPAddress) -> String {
            let text = "\(address)"
            if let percent = text.firstIndex(of: "%") {
                return String(text[..<percent])
            }
            return text
        }
    }
#endif

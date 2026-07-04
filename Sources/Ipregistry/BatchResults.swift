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

/// The `{"results": [...]}` envelope returned by batch endpoints, where each
/// element is either a `Value` or an API error object. An element is treated
/// as an error when it carries a non-null `"code"` field, which `Value`
/// payloads never do.
struct ResultsEnvelope<Value: Decodable>: Decodable {
    let results: [Result<Value, APIError>]

    private enum CodingKeys: String, CodingKey {
        case results
    }

    private struct Entry: Decodable {
        let result: Result<Value, APIError>

        private enum ProbeKeys: String, CodingKey {
            case code
        }

        init(from decoder: any Decoder) throws {
            let probe = try decoder.container(keyedBy: ProbeKeys.self)
            if probe.contains(.code), try !probe.decodeNil(forKey: .code) {
                let payload = try APIErrorPayload(from: decoder)
                result = .failure(payload.apiError)
            } else {
                result = .success(try Value(from: decoder))
            }
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try container.decodeIfPresent([Entry].self, forKey: .results) ?? []
        results = entries.map(\.result)
    }
}

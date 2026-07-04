// Resolves several IP addresses in a single request. Each entry may
// independently succeed or fail:
//
//   IPREGISTRY_API_KEY=YOUR_API_KEY swift run batch

import Foundation
import Ipregistry

guard let apiKey = ProcessInfo.processInfo.environment["IPREGISTRY_API_KEY"] else {
    print("Set the IPREGISTRY_API_KEY environment variable and try again.")
    exit(1)
}

// Enable caching so repeated addresses are served locally.
let client = IpregistryClient(apiKey: apiKey, cache: InMemoryCache())

let ips = ["73.2.2.2", "8.8.8.8", "2001:67c:2e8:22::c100:68b", "not-an-ip"]

do {
    let results = try await client.lookupBatch(ips)
    for (ip, result) in zip(ips, results) {
        switch result {
        case .success(let info):
            print("\(ip): \(info.location.country.name ?? "unknown country")")
        case .failure(let error):
            print("\(ip): failed — \(error)")
        }
    }
} catch {
    print("The batch request failed: \(error)")
    exit(1)
}

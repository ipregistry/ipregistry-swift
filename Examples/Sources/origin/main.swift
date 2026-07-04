// Looks up the IP address the request originates from:
//
//   IPREGISTRY_API_KEY=YOUR_API_KEY swift run origin

import Foundation
import Ipregistry

guard let apiKey = ProcessInfo.processInfo.environment["IPREGISTRY_API_KEY"] else {
    print("Set the IPREGISTRY_API_KEY environment variable and try again.")
    exit(1)
}

let client = IpregistryClient(apiKey: apiKey)

do {
    let origin = try await client.lookupOrigin()
    print("Your IP:      \(origin.ip ?? "-")")
    print("Your country: \(origin.location.country.name ?? "-")")
    print("Your browser: \(origin.userAgent?.name ?? "-")")
    print("Your OS:      \(origin.userAgent?.operatingSystem.name ?? "-")")
} catch {
    print("The request failed: \(error)")
    exit(1)
}

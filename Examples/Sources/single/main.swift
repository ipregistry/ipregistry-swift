// Looks up a single IP address:
//
//   IPREGISTRY_API_KEY=YOUR_API_KEY swift run single

import Foundation
import Ipregistry

guard let apiKey = ProcessInfo.processInfo.environment["IPREGISTRY_API_KEY"] else {
    print("Set the IPREGISTRY_API_KEY environment variable and try again.")
    exit(1)
}

let client = IpregistryClient(apiKey: apiKey)

do {
    let info = try await client.lookup("54.85.132.205", options: LookupOptions(hostname: true))
    print("IP:        \(info.ip ?? "-")")
    print("Type:      \(info.type?.rawValue ?? "-")")
    print("Hostname:  \(info.hostname ?? "-")")
    print("Country:   \(info.location.country.name ?? "-") \(info.location.country.flag.emoji ?? "")")
    print("City:      \(info.location.city ?? "-")")
    print("ASN:       \(info.connection.asn.map(String.init) ?? "-")")
    print("Company:   \(info.company.name ?? "-")")
    print("Time zone: \(info.timeZone.id ?? "-")")
    print("VPN:       \(info.security.isVPN)")
} catch let error as APIError {
    print("The API reported an error: \(error)")
    exit(1)
} catch {
    print("The request failed: \(error)")
    exit(1)
}

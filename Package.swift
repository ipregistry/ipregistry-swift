// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Ipregistry",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "Ipregistry", targets: ["Ipregistry"])
    ],
    targets: [
        .target(name: "Ipregistry"),
        .testTarget(
            name: "IpregistryTests",
            dependencies: ["Ipregistry"]
        ),
        .testTarget(
            name: "IpregistrySystemTests",
            dependencies: ["Ipregistry"]
        ),
    ]
)

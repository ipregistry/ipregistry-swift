// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "IpregistryExamples",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        // The explicit name keeps the dependency resolvable whatever the
        // checkout directory is called.
        .package(name: "Ipregistry", path: "..")
    ],
    targets: [
        .executableTarget(
            name: "single",
            dependencies: ["Ipregistry"]
        ),
        .executableTarget(
            name: "origin",
            dependencies: ["Ipregistry"]
        ),
        .executableTarget(
            name: "batch",
            dependencies: ["Ipregistry"]
        ),
    ]
)

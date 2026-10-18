// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LaunchpadApp",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LaunchpadCore", targets: ["LaunchpadCore"]),
        .executable(name: "LaunchpadApp", targets: ["LaunchpadApp"])
    ],
    targets: [
        .target(name: "LaunchpadCore"),
        .executableTarget(name: "LaunchpadApp", dependencies: ["LaunchpadCore"]),
        .executableTarget(name: "LaunchpadCoreChecks", dependencies: ["LaunchpadCore"])
    ]
)

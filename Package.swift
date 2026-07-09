// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AgentIsland",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AgentIsland", targets: ["AgentIsland"])
    ],
    targets: [
        .executableTarget(name: "AgentIsland")
    ]
)

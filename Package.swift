// swift-tools-version: 5.9
// Copyright (c) 2026 Ling
// SPDX-License-Identifier: MIT

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
        .executableTarget(name: "AgentIsland"),
        .testTarget(
            name: "AgentIslandTests",
            dependencies: ["AgentIsland"]
        )
    ]
)

// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AgentWatch",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.1")
    ],
    targets: [
        .target(
            name: "AgentWatchLib",
            dependencies: ["HotKey"],
            path: "Sources",
            exclude: ["App"]
        ),
        .executableTarget(
            name: "AgentWatch",
            dependencies: ["AgentWatchLib"],
            path: "Sources/App"
        ),
        .executableTarget(
            name: "AgentWatchTests",
            dependencies: ["AgentWatchLib"],
            path: "Tests"
        )
    ]
)

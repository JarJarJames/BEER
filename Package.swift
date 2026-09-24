// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "BEER",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BEER", targets: ["BEER"])
    ],
    targets: [
        .target(
            name: "AchievementUI",
            path: "Sources/AchievementUI"
        ),
        .executableTarget(
            name: "BEER",
            dependencies: ["AchievementUI"],
            path: "Sources/BEER",
            resources: [.copy("Resources/achievement-unlock.mp3")],
            plugins: ["CloudSyncPrebuild"]
        ),
        .testTarget(
            name: "BEERTests",
            dependencies: ["BEER", "AchievementUI"],
            path: "Tests/BEERTests"
        ),
        .plugin(
            name: "CloudSyncPrebuild",
            capability: .buildTool(),
            path: "Plugins/CloudSyncPrebuild"
        )
    ]
)

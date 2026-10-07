// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "BEER",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BEER", targets: ["BEER"]),
        // Declared as a product (not just an internal target) so Xcode
        // generates a separate scheme for it — that's what lets its own
        // Previews use a lightweight library host instead of needing BEER's
        // executable target to support ENABLE_DEBUG_DYLIB.
        .library(name: "AchievementUI", targets: ["AchievementUI"])
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

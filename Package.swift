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
        .executableTarget(
            name: "BEER",
            path: "Sources/BEER"
        )
    ]
)

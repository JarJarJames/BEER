// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GameNativeMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GameNativeMac", targets: ["GameNativeMac"])
    ],
    targets: [
        .executableTarget(
            name: "GameNativeMac",
            path: "Sources/GameNativeMac"
        )
    ]
)

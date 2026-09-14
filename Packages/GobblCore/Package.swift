// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GobblCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GobblCore", targets: ["GobblCore"]),
    ],
    targets: [
        .target(
            name: "GobblCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "GobblCoreTests",
            dependencies: ["GobblCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

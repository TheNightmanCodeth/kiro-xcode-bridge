// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "kiro-bridge",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        // Library target — all logic lives here, importable by tests
        .executableTarget(
            name: "KiroBridge",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/KiroBridge",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // Tests import KiroBridgeCore
        .testTarget(
            name: "KiroBridgeTests",
            dependencies: ["KiroBridge"],
            path: "Tests/KiroBridgeTests"
        ),
    ]
)

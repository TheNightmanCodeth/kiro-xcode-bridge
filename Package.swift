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
        // sqlite3 system library — works on both macOS and Linux
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite",
            pkgConfig: "sqlite3",
            providers: [.apt(["libsqlite3-dev"]), .brew(["sqlite3"])]
        ),
        // Library target — all logic lives here, importable by tests
        .target(
            name: "KiroBridgeCore",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "CSQLite",
            ],
            path: "Sources/KiroBridgeCore"
        ),
        // Thin executable target — just calls KiroBridgeCommand.main()
        .executableTarget(
            name: "kiro-bridge",
            dependencies: ["KiroBridgeCore"],
            path: "Sources/kiro-bridge"
        ),
        // Tests import KiroBridgeCore
        .testTarget(
            name: "KiroBridgeTests",
            dependencies: ["KiroBridgeCore"],
            path: "Tests/KiroBridgeTests"
        ),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "eventkitctl",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "eventkitctl", targets: ["eventkitctl"]),
        .library(name: "AppCore", targets: ["AppCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
    ],
    targets: [
        .target(
            name: "AppCore"
        ),
        .executableTarget(
            name: "eventkitctl",
            dependencies: [
                "AppCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "MCP", package: "swift-sdk"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist",
                ])
            ]
        ),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SystemMCP",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "systemmcp", targets: ["SystemMCP"]),
        .library(name: "SystemMCPCore", targets: ["SystemMCPCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        // Shared library: EventKit wrapper infrastructure, response models, logging,
        // errors, date parsing, MCP/CLI helpers, and the reminder/calendar domain logic.
        .target(
            name: "SystemMCPCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        // systemmcp: single binary with `reminder` and `calendar` subcommands, each
        // exposing a CLI and an MCP server (`systemmcp reminder serve` / `systemmcp calendar serve`).
        .executableTarget(
            name: "SystemMCP",
            dependencies: [
                "SystemMCPCore",
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

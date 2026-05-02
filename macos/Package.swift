// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "trusted_time",
    platforms: [
        .macOS("10.14")
    ],
    products: [
        .library(name: "trusted_time", targets: ["trusted_time"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "trusted_time",
            dependencies: [],
            path: "../darwin/trusted_time",
            sources: ["Classes"],
            resources: [
                .process("Resources")
            ]
        )
    ]
)

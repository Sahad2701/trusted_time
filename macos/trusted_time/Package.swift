// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "trusted_time",
    platforms: [
        .macOS("10.14")
    ],
    products: [
        .library(name: "trusted-time", targets: ["trusted_time"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "trusted_time",
            dependencies: []
        )
    ]
)

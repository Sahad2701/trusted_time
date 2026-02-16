// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "trusted_time",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        .library(name: "trusted_time", targets: ["trusted_time"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "trusted_time",
            dependencies: [],
            path: "ios/Classes"
        )
    ]
)


// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "trusted_time",
    platforms: [
        .iOS(.v11)
    ],
    products: [
        .library(
            name: "trusted_time",
            targets: ["trusted_time"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "trusted_time",
            dependencies: [],
            path: "Classes"
        )
    ]
)

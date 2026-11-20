// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "EFCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "EFCore", targets: ["EFCore"]),
    ],
    targets: [
        .target(name: "EFCore"),
        .testTarget(name: "EFCoreTests", dependencies: ["EFCore"]),
    ]
)

// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "EFPersistence",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "EFPersistence", targets: ["EFPersistence"]),
    ],
    dependencies: [
        .package(path: "../EFCore"),
    ],
    targets: [
        .target(
            name: "EFPersistence",
            dependencies: ["EFCore"]
        ),
        .testTarget(
            name: "EFPersistenceTests",
            dependencies: ["EFPersistence"]
        ),
    ]
)

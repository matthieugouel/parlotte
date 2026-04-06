// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Parlotte",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../ParlotteSDK"),
    ],
    targets: [
        .executableTarget(
            name: "Parlotte",
            dependencies: [
                .product(name: "ParlotteSDK", package: "ParlotteSDK"),
            ],
            path: "Sources",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Parlotte",
    platforms: [.macOS(.v15)],
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
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)

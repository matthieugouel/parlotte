// swift-tools-version: 6.0
import PackageDescription

let testingFlags: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .unsafeFlags([
        "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
    ]),
]

let testingLinkerFlags: [LinkerSetting] = [
    .unsafeFlags([
        "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
        "-framework", "Testing",
        "-Xlinker", "-rpath",
        "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
    ]),
]

let package = Package(
    name: "Parlotte",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../ParlotteSDK"),
    ],
    targets: [
        .target(
            name: "ParlotteLib",
            dependencies: [
                .product(name: "ParlotteSDK", package: "ParlotteSDK"),
            ],
            path: "Sources/ParlotteLib",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .executableTarget(
            name: "Parlotte",
            dependencies: [
                "ParlotteLib",
                .product(name: "ParlotteSDK", package: "ParlotteSDK"),
            ],
            path: "Sources/ParlotteApp",
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        // Test suite as a library — tests are discovered via Swift Testing metadata
        .target(
            name: "ParlotteTestSuite",
            dependencies: [
                "ParlotteLib",
                .product(name: "ParlotteSDK", package: "ParlotteSDK"),
            ],
            path: "Tests",
            swiftSettings: testingFlags,
            linkerSettings: testingLinkerFlags
        ),
        // Executable runner — works without Xcode (no xctest needed)
        .executableTarget(
            name: "TestRunner",
            dependencies: ["ParlotteTestSuite"],
            path: "Sources/TestRunner",
            swiftSettings: testingFlags,
            linkerSettings: testingLinkerFlags
        ),
    ]
)

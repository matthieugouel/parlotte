// swift-tools-version: 6.0
import PackageDescription

// Point Swift Testing at the Xcode toolchain's Testing.framework (which matches
// the macros emitted by the current swift compiler). The CommandLineTools copy
// is often stale and triggers `__uncheckedFileID` / `fileID` init mismatches.
let xcodeFrameworksPath = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks"

let testingFlags: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .unsafeFlags([
        "-F", xcodeFrameworksPath,
    ]),
]

let testingLinkerFlags: [LinkerSetting] = [
    .unsafeFlags([
        "-F", xcodeFrameworksPath,
        "-framework", "Testing",
        "-Xlinker", "-rpath",
        "-Xlinker", xcodeFrameworksPath,
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

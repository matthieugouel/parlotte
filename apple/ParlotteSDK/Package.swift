// swift-tools-version: 5.10
import PackageDescription
import Foundation

let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let rustLibDir = "\(packageDir)/RustFramework"

let package = Package(
    name: "ParlotteSDK",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ParlotteSDK", targets: ["ParlotteSDK"]),
    ],
    targets: [
        // C headers + static library for the Rust FFI
        .systemLibrary(
            name: "ParlotteFFIHeaders",
            path: "Sources/ParlotteFFIHeaders"
        ),
        // UniFFI-generated Swift bindings (auto-generated, do not edit)
        .target(
            name: "ParlotteFFI",
            dependencies: ["ParlotteFFIHeaders"],
            path: "Sources/ParlotteFFI",
            linkerSettings: [
                .unsafeFlags([
                    "-L", rustLibDir,
                    "-lparlotte_ffi",
                    // blake3 ships a pre-compiled neon assembly object built with a
                    // newer macOS SDK; suppress the harmless version-mismatch warning.
                    "-Xlinker", "-w",
                ]),
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
                .linkedLibrary("resolv"),
                .linkedLibrary("sqlite3"),
            ]
        ),
        // Hand-written Swift wrapper: async actor API
        .target(
            name: "ParlotteSDK",
            dependencies: ["ParlotteFFI"],
            path: "Sources/ParlotteSDK"
        ),
    ]
)

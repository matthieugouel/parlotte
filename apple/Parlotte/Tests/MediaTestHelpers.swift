import Foundation

/// Helpers for attachment/media tests. Kept in a separate file so the main
/// test file doesn't need to `import Foundation` — which conflicts with
/// `import Testing` in some toolchain configurations.
enum MediaTestHelpers {
    static func pngMagicBytes() -> Data {
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    static func bytes(_ octets: [UInt8]) -> Data {
        Data(octets)
    }

    static func stringBytes(_ text: String) -> Data {
        Data(text.utf8)
    }

    /// Write `contents` to a tempfile named `name` and return the URL.
    static func makeTempFile(name: String, contents: Data) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? contents.write(to: url)
        return url
    }

    static func removeTempFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - UserDefaults

    static func setDefault(_ value: String, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    static func getDefaultString(forKey key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    static func removeDefault(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

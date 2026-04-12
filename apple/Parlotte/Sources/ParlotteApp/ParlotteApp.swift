import AppKit
import ParlotteLib
import ParlotteSDK
import SwiftUI

@main
struct ParlotteApp: App {
    @State private var appState: AppState

    init() {
        let profile = Self.parseProfile()
        if CommandLine.arguments.contains("--debug") {
            initLogging(level: "debug")
        }
        _appState = State(initialValue: AppState(profile: profile))
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .defaultSize(width: 800, height: 600)
        .windowStyle(.hiddenTitleBar)
    }

    private static func parseProfile() -> String {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--profile"), idx + 1 < args.count {
            return args[idx + 1]
        }
        return "default"
    }
}

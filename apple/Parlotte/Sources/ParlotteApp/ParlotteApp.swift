import AppKit
import ParlotteLib
import ParlotteSDK
import SwiftUI

@main
struct ParlotteApp: App {
    @State private var appState: AppState
    /// Retained so the listener stays alive for the lifetime of the app.
    private static var debugServer: DebugServer?

    init() {
        let profile = Self.parseProfile()
        if CommandLine.arguments.contains("--debug") {
            initLogging(level: "debug")
        }
        let state = AppState(profile: profile)
        _appState = State(initialValue: state)

        if let port = Self.parseDebugIpcPort() {
            let server = DebugServer(appState: state)
            do {
                try server.start(port: port)
                Self.debugServer = server
                print("Debug IPC server listening on 127.0.0.1:\(port)")
            } catch {
                print("Failed to start debug IPC server on port \(port): \(error)")
            }
        }

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(appState.appearance.colorScheme)
                .tint(AppColor.accent)
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

    private static func parseDebugIpcPort() -> UInt16? {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--debug-ipc-port"), idx + 1 < args.count {
            return UInt16(args[idx + 1])
        }
        return nil
    }
}

extension AppearanceMode {
    /// Maps to SwiftUI's `ColorScheme?`. `nil` means follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var displayLabel: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

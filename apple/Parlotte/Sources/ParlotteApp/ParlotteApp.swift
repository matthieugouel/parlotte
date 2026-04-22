import AppKit
import ParlotteLib
import ParlotteSDK
import SwiftUI

@main
struct ParlotteApp: App {
    @State private var appState: AppState
    /// Retained so the listener stays alive for the lifetime of the app.
    private static var debugServer: DebugServer?
    /// Retained so the UNUserNotificationCenter delegate isn't released mid-flight.
    private static var notificationDispatcher: LocalNotificationDispatcher?

    init() {
        let profile = Self.parseProfile()
        if CommandLine.arguments.contains("--debug") {
            initLogging(level: "debug")
        }
        let state = AppState(profile: profile)
        _appState = State(initialValue: state)

        let dispatcher = LocalNotificationDispatcher()
        dispatcher.install()
        dispatcher.onTap = { [weak state] roomId in
            state?.openRoom(roomId)
        }
        state.notificationDispatcher = dispatcher
        Self.notificationDispatcher = dispatcher
        Task { _ = await dispatcher.requestAuthorization() }

        if let port = Self.parseDebugIpcPort() {
            // Generate a per-session bearer token and surface it on stderr.
            // Without this, any local process (or a DNS-rebinding web page)
            // could drive the IPC to read `pendingRecoveryKey` or confirm
            // SAS verification on the user's behalf.
            let token = AppState.randomToken(byteCount: 24)
            let server = DebugServer(appState: state, authToken: token)
            do {
                try server.start(port: port)
                Self.debugServer = server
                FileHandle.standardError.write(Data("Debug IPC listening on 127.0.0.1:\(port) (token: \(token))\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("Failed to start debug IPC server on port \(port): \(error)\n".utf8))
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
        guard let idx = args.firstIndex(of: "--profile"), idx + 1 < args.count else {
            return "default"
        }
        let raw = args[idx + 1]
        // The profile string becomes both a filesystem path component
        // (`~/.../Parlotte/<profile>`) and a UserDefaults key prefix. Reject
        // anything outside a conservative allowlist so `../` or `.` can't
        // escape the store dir or collide keys across profiles.
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        let valid = !raw.isEmpty
            && raw.count <= 64
            && raw.unicodeScalars.allSatisfy { allowed.contains($0) }
        if !valid {
            FileHandle.standardError.write(Data("Invalid --profile: must match [A-Za-z0-9_-]{1,64}\n".utf8))
            exit(2)
        }
        return raw
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

import AppKit
import Foundation
import UserNotifications

/// Posts OS-level notifications for incoming messages.
///
/// Split into a protocol so tests can inject a mock and verify which
/// notifications would fire without touching `UNUserNotificationCenter`.
@MainActor
public protocol NotificationDispatcher: AnyObject {
    func requestAuthorization() async -> Bool
    func postMessageNotification(roomId: String, title: String, body: String)
}

/// Default dispatcher backed by `UNUserNotificationCenter`. Also acts as the
/// delegate so taps route back to the app via the `onTap` callback.
@MainActor
public final class LocalNotificationDispatcher: NSObject, NotificationDispatcher {
    /// Invoked on the main actor when the user taps a notification.
    /// The string is the room ID encoded into the notification's userInfo.
    public var onTap: ((String) -> Void)?

    /// Nil when the process isn't running from a proper .app bundle
    /// (e.g. under `swift run`). `UNUserNotificationCenter.current()` raises
    /// an NSException in that case, so every operation becomes a no-op during
    /// SPM-based development.
    private let center: UNUserNotificationCenter?

    public override init() {
        self.center = Bundle.main.bundleIdentifier != nil ? UNUserNotificationCenter.current() : nil
        super.init()
    }

    /// Installs this object as the shared notification center's delegate.
    /// Must be called once at app launch — delegates that aren't installed by
    /// the time a notification is delivered will miss the tap event.
    public func install() {
        center?.delegate = self
    }

    public func requestAuthorization() async -> Bool {
        guard let center else { return false }
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    public func postMessageNotification(roomId: String, title: String, body: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["roomId": roomId]
        // Unique identifier so macOS doesn't coalesce successive messages from
        // the same room into a single banner.
        let request = UNNotificationRequest(
            identifier: "parlotte.msg.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}

extension LocalNotificationDispatcher: UNUserNotificationCenterDelegate {
    /// Always show banners, even when the app is frontmost. AppState already
    /// filters out notifications for the currently-selected room.
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let roomId = userInfo["roomId"] as? String else { return }
        await handleTap(roomId: roomId)
    }

    @MainActor
    private func handleTap(roomId: String) {
        NSApp.activate(ignoringOtherApps: true)
        onTap?(roomId)
    }
}

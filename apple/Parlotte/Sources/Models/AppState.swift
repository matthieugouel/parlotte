import AppKit
import Foundation
import ParlotteSDK

@Observable
@MainActor
final class AppState {
    let profile: String

    var isLoggedIn = false
    var isLoading = false
    var isCheckingSession = true
    var errorMessage: String?
    var loggedInUserId: String?
    var isSyncActive = false

    var rooms: [RoomInfo] = []
    var selectedRoomId: String? {
        didSet {
            messages = []
            if let roomId = selectedRoomId {
                // Optimistically clear unread count immediately
                if let idx = rooms.firstIndex(where: { $0.id == roomId }) {
                    rooms[idx].unreadCount = 0
                }
                Task {
                    await refreshMessages()
                    await sendReadReceiptForLatestMessage()
                }
            }
        }
    }
    var messages: [MessageInfo] = []

    var homeserverURL = "http://localhost:8008"
    var username = ""
    var password = ""

    // SSO state
    var ssoProviders: [SsoProvider] = []
    var supportsPassword = true
    var supportsSso = false
    var isDetectingLoginMethods = false

    private var client: MatrixClient?

    init(profile: String = "default") {
        self.profile = profile
    }

    func detectLoginMethods() async {
        isDetectingLoginMethods = true
        errorMessage = nil

        do {
            let storePath = storePath()
            let client = try MatrixClient(homeserverURL: homeserverURL, storePath: storePath)
            let methods = try await client.loginMethods()
            supportsPassword = methods.supportsPassword
            supportsSso = methods.supportsSso
            ssoProviders = methods.ssoProviders
            // Keep client around for SSO flow
            self.client = client
        } catch {
            supportsPassword = true
            supportsSso = false
            ssoProviders = []
        }

        isDetectingLoginMethods = false
    }

    func loginWithSso(idpId: String? = nil) async {
        isLoading = true
        errorMessage = nil

        do {
            if client == nil {
                let storePath = storePath()
                clearStore()
                client = try MatrixClient(homeserverURL: homeserverURL, storePath: storePath)
            }
            guard let client else { return }

            // Start a local HTTP server to receive the SSO callback
            let server = SsoCallbackServer()
            let port = try await server.start()
            let redirectUrl = "http://localhost:\(port)"

            let ssoUrl = try await client.ssoLoginUrl(redirectUrl: redirectUrl, idpId: idpId)

            // Open SSO URL in system browser
            if let url = URL(string: ssoUrl) {
                NSWorkspace.shared.open(url)
            }

            // Wait for the browser to redirect back with the login token
            let callbackUrl = try await server.waitForCallback()

            let session = try await client.loginSsoCallback(callbackUrl: callbackUrl)
            let sessionData = await client.session()
            saveSession(sessionData, homeserverURL: homeserverURL)
            self.loggedInUserId = session.userId
            password = ""
            isLoggedIn = true
            isSyncActive = true
            try await client.syncOnce()
            await refreshRooms()
            startSyncLoop()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func login() async {
        isLoading = true
        errorMessage = nil

        do {
            clearStore()
            let storePath = storePath()
            let client = try MatrixClient(homeserverURL: homeserverURL, storePath: storePath)
            _ = try await client.login(username: username, password: password)
            let session = await client.session()
            saveSession(session, homeserverURL: homeserverURL)
            self.client = client
            self.loggedInUserId = session?.userId
            password = ""
            isLoggedIn = true
            isSyncActive = true
            try await client.syncOnce()
            await refreshRooms()
            startSyncLoop()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func restoreSession() async {
        guard let saved = loadSession() else {
            isCheckingSession = false
            return
        }

        do {
            let storePath = storePath()
            let client = try MatrixClient(homeserverURL: saved.homeserverURL, storePath: storePath)
            try await client.restoreSession(MatrixSessionData(
                userId: saved.userId,
                deviceId: saved.deviceId,
                accessToken: saved.accessToken
            ))
            self.homeserverURL = saved.homeserverURL
            self.client = client
            self.loggedInUserId = saved.userId
            await refreshRooms()
            isLoggedIn = true
            isSyncActive = true
            isCheckingSession = false
            try await client.syncOnce()
            await refreshRooms()
            startSyncLoop()
        } catch {
            clearSavedSession()
            clearStore()
            isCheckingSession = false
        }
    }

    func logout() async {
        client?.stopSync()
        isSyncActive = false
        try? await client?.logout()
        client = nil
        isLoggedIn = false
        loggedInUserId = nil
        rooms = []
        selectedRoomId = nil
        clearSavedSession()
        clearStore()
    }

    func refreshRooms() async {
        guard let client else { return }
        do {
            var updated = try await client.rooms()
            // Clear unread count for the room the user is currently viewing
            if let selected = selectedRoomId,
               let idx = updated.firstIndex(where: { $0.id == selected }) {
                updated[idx].unreadCount = 0
            }
            rooms = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshMessages() async {
        guard let client, let roomId = selectedRoomId else {
            messages = []
            return
        }
        do {
            messages = try await client.messages(roomId: roomId)
        } catch {
            // Non-fatal — messages may not be available yet
        }
    }

    func sendMessage(body: String) async {
        guard let client, let roomId = selectedRoomId else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try await client.sendMessage(roomId: roomId, body: trimmed)
            // Persistent sync will pick up the new message; no syncOnce needed
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createRoom(name: String, isPublic: Bool) async {
        guard let client else { return }
        do {
            _ = try await client.createRoom(name: name, isPublic: isPublic)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchPublicRooms() async -> [PublicRoomInfo] {
        guard let client else { return [] }
        do {
            return try await client.publicRooms()
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func joinRoom(roomId: String) async {
        guard let client else { return }
        do {
            try await client.joinRoom(roomId: roomId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchRoomMembers(roomId: String) async -> [RoomMemberInfo] {
        guard let client else { return [] }
        do {
            return try await client.roomMembers(roomId: roomId)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func leaveRoom(roomId: String) async {
        guard let client else { return }
        do {
            try await client.leaveRoom(roomId: roomId)
            if selectedRoomId == roomId {
                selectedRoomId = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func editMessage(eventId: String, newBody: String) async {
        guard let client, let roomId = selectedRoomId else { return }
        do {
            try await client.editMessage(roomId: roomId, eventId: eventId, newBody: newBody)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteMessage(eventId: String) async {
        guard let client, let roomId = selectedRoomId else { return }
        do {
            try await client.redactMessage(roomId: roomId, eventId: eventId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendReadReceipt(roomId: String) async {
        guard let client, let lastMessage = messages.last else { return }
        do {
            try await client.sendReadReceipt(roomId: roomId, eventId: lastMessage.eventId)
        } catch {
            // Non-fatal — read receipts are best-effort
        }
    }

    func inviteUser(userId: String) async {
        guard let client, let roomId = selectedRoomId else { return }
        do {
            try await client.inviteUser(roomId: roomId, userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    fileprivate func sendReadReceiptForLatestMessage() async {
        guard let roomId = selectedRoomId else { return }
        await sendReadReceipt(roomId: roomId)
    }

    private func startSyncLoop() {
        guard let client else { return }
        isSyncActive = true

        let listener = SyncUpdateHandler(appState: self)
        do {
            try client.startSync(listener: listener)
        } catch {
            isSyncActive = false
        }
    }

    private func clearStore() {
        let dir = Self.storeDir(profile: profile)
        try? FileManager.default.removeItem(at: dir)
    }

    private func storePath() -> String {
        let dir = Self.storeDir(profile: profile)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    private static func storeDir(profile: String) -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("Parlotte", isDirectory: true)
            .appendingPathComponent(profile, isDirectory: true)
    }

    // MARK: - Session persistence

    private struct SavedSession {
        let homeserverURL: String
        let userId: String
        let deviceId: String
        let accessToken: String
    }

    private static let defaults = UserDefaults.standard

    private func key(_ name: String) -> String {
        "parlotte.\(profile).\(name)"
    }

    private func saveSession(_ data: MatrixSessionData?, homeserverURL: String) {
        guard let data else { return }
        let d = Self.defaults
        d.set(homeserverURL,    forKey: key("homeserver"))
        d.set(data.userId,      forKey: key("userId"))
        d.set(data.deviceId,    forKey: key("deviceId"))
        d.set(data.accessToken, forKey: key("accessToken"))
    }

    private func loadSession() -> SavedSession? {
        let d = Self.defaults
        guard
            let hs    = d.string(forKey: key("homeserver")),
            let uid   = d.string(forKey: key("userId")),
            let did   = d.string(forKey: key("deviceId")),
            let token = d.string(forKey: key("accessToken"))
        else { return nil }
        return SavedSession(
            homeserverURL: hs,
            userId: uid,
            deviceId: did,
            accessToken: token
        )
    }

    private func clearSavedSession() {
        let d = Self.defaults
        d.removeObject(forKey: key("homeserver"))
        d.removeObject(forKey: key("userId"))
        d.removeObject(forKey: key("deviceId"))
        d.removeObject(forKey: key("accessToken"))
    }
}

/// Bridge from Rust sync callback to Swift MainActor.
/// Called on a background thread by the Rust sync loop.
private final class SyncUpdateHandler: ParlotteSyncListener, @unchecked Sendable {
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func onSyncUpdate() {
        Task { @MainActor [weak appState] in
            guard let appState else { return }
            await appState.refreshRooms()
            await appState.refreshMessages()
            await appState.sendReadReceiptForLatestMessage()
        }
    }
}

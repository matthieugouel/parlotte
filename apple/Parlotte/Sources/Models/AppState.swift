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

    var rooms: [RoomInfo] = []
    var selectedRoomId: String? {
        didSet {
            messages = []
            if selectedRoomId != nil {
                Task { await refreshMessages() }
            }
        }
    }
    var messages: [MessageInfo] = []

    var homeserverURL = "http://localhost:8008"
    var username = ""
    var password = ""

    private var client: MatrixClient?
    private var syncTask: Task<Void, Never>?

    init(profile: String = "default") {
        self.profile = profile
    }

    func login() async {
        isLoading = true
        errorMessage = nil

        do {
            clearStore()
            let storePath = storePath()
            let client = try MatrixClient(homeserverURL: homeserverURL, storePath: storePath)
            _ = try await client.login(username: username, password: password)
            saveSession(await client.session(), homeserverURL: homeserverURL)
            self.client = client
            password = ""
            isLoggedIn = true
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
            await refreshRooms()
            isLoggedIn = true
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
        syncTask?.cancel()
        syncTask = nil
        try? await client?.logout()
        client = nil
        isLoggedIn = false
        rooms = []
        selectedRoomId = nil
        clearSavedSession()
        clearStore()
    }

    func refreshRooms() async {
        guard let client else { return }
        do {
            rooms = try await client.rooms()
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
            try await client.syncOnce()
            await refreshMessages()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createRoom(name: String, isPublic: Bool) async {
        guard let client else { return }
        do {
            _ = try await client.createRoom(name: name, isPublic: isPublic)
            try await client.syncOnce()
            await refreshRooms()
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
            try await client.syncOnce()
            await refreshRooms()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func leaveRoom(roomId: String) async {
        guard let client else { return }
        do {
            try await client.leaveRoom(roomId: roomId)
            if selectedRoomId == roomId {
                selectedRoomId = nil
            }
            try await client.syncOnce()
            await refreshRooms()
        } catch {
            errorMessage = error.localizedDescription
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

    private func startSyncLoop() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                guard let self, let client = self.client else { break }
                do {
                    try await client.syncOnce()
                    await self.refreshRooms()
                    await self.refreshMessages()
                } catch {
                    // Sync errors are transient — retry next cycle
                }
            }
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

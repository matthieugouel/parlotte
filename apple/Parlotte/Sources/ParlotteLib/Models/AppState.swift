import AppKit
import Foundation
import ParlotteSDK
import UniformTypeIdentifiers

@Observable
@MainActor
public final class AppState {
    public let profile: String

    public var isLoggedIn = false
    public var isLoading = false
    public var isCheckingSession = true
    public var errorMessage: String?
    public var loggedInUserId: String?
    public var isSyncActive = false

    public var rooms: [RoomInfo] = []
    public var selectedRoomId: String? {
        didSet {
            // Cancel typing indicator for the room we're leaving
            if let oldRoom = oldValue, let client {
                Task {
                    try? await client.sendTypingNotice(roomId: oldRoom, isTyping: false)
                }
            }
            messages = []
            messageEndToken = nil
            hasMoreMessages = false
            if let roomId = selectedRoomId {
                // Optimistically clear unread count immediately
                if let idx = rooms.firstIndex(where: { $0.id == roomId }) {
                    rooms[idx].unreadCount = 0
                }
                roomRefreshTask = Task {
                    await refreshMessages()
                    await sendReadReceiptForLatestMessage()
                }
            }
        }
    }
    /// Task spawned by `selectedRoomId.didSet` to refresh messages.
    /// Exposed as internal so tests can await its completion before asserting.
    var roomRefreshTask: Task<Void, Never>?
    public var messages: [MessageInfo] = []
    public var hasMoreMessages = false
    public var isLoadingMoreMessages = false
    private var messageEndToken: String?

    /// Maps room ID to the list of user IDs currently typing (excluding own user).
    public var typingUsers: [String: [String]] = [:]

    /// User IDs typing in the currently selected room.
    public var currentRoomTypingUsers: [String] {
        guard let roomId = selectedRoomId else { return [] }
        return typingUsers[roomId] ?? []
    }

    public var homeserverURL = "http://localhost:8008"
    public var username = ""
    public var password = ""

    // SSO state
    public var ssoProviders: [SsoProvider] = []
    public var supportsPassword = true
    public var supportsSso = false
    public var isDetectingLoginMethods = false

    public var client: (any MatrixClientProtocol)?

    public init(profile: String = "default") {
        self.profile = profile
    }

    public func detectLoginMethods() async {
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

    public func loginWithSso(idpId: String? = nil) async {
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

    public func login() async {
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

    public func restoreSession() async {
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

    public func logout() async {
        client?.stopSync()
        isSyncActive = false
        try? await client?.logout()
        client = nil
        isLoggedIn = false
        loggedInUserId = nil
        rooms = []
        typingUsers = [:]
        selectedRoomId = nil
        pendingAttachments.removeAll()
        mediaCache.removeAllObjects()
        clearSavedSession()
        clearStore()
    }

    /// Bytes for optimistic attachment messages, keyed on the placeholder event ID.
    /// Removed when the server-side event replaces the placeholder on sync.
    public var pendingAttachments: [String: Data] = [:]

    /// In-memory cache of downloaded media bytes keyed on mxc:// URI.
    /// Auto-evicts under memory pressure.
    public let mediaCache = NSCache<NSString, NSData>()

    /// Refresh the room list. Returns true if the selected room has new unread messages.
    @discardableResult
    public func refreshRooms() async -> Bool {
        guard let client else { return false }
        do {
            var updated = try await client.rooms()
            // Check if the selected room has new messages before zeroing
            var hasNewMessages = false
            if let selected = selectedRoomId,
               let idx = updated.firstIndex(where: { $0.id == selected }) {
                hasNewMessages = updated[idx].unreadCount > 0
                updated[idx].unreadCount = 0
            }
            rooms = updated
            return hasNewMessages
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func refreshMessages() async {
        guard let client, let roomId = selectedRoomId else {
            messages = []
            return
        }
        do {
            let batch = try await client.messages(roomId: roomId, limit: 50, from: nil)
            messages = batch.messages
            messageEndToken = batch.endToken
            hasMoreMessages = batch.endToken != nil
        } catch {
            // Non-fatal — messages may not be available yet
        }
    }

    /// Called on sync — checks for new messages, edits, and redactions.
    /// Minimises array mutations to avoid unnecessary SwiftUI re-renders.
    public func appendNewMessages() async {
        guard let client, let roomId = selectedRoomId, !messages.isEmpty else { return }
        do {
            let batch = try await client.messages(roomId: roomId, limit: 50, from: nil)
            let serverMessages = batch.messages
            let serverById = Dictionary(
                serverMessages.map { ($0.eventId, $0) },
                uniquingKeysWith: { _, last in last }
            )

            var changed = false

            // 1. Update edited messages in place
            for i in messages.indices {
                if let serverMsg = serverById[messages[i].eventId] {
                    if messages[i].body != serverMsg.body
                        || messages[i].isEdited != serverMsg.isEdited
                        || messages[i].reactions != serverMsg.reactions
                    {
                        messages[i] = serverMsg
                        changed = true
                    }
                }
            }

            // 2. Remove redacted messages — only those recent enough that the
            //    server batch should contain them (preserves older paginated messages
            //    and in-flight optimistic placeholders)
            let serverIds = Set(serverMessages.map(\.eventId))
            if let oldestServerTs = serverMessages.first?.timestampMs {
                let before = messages.count
                messages.removeAll { msg in
                    !msg.eventId.hasPrefix("~optimistic:")
                        && msg.timestampMs >= oldestServerTs
                        && !serverIds.contains(msg.eventId)
                }
                if messages.count != before { changed = true }
            }

            // 3. Add genuinely new messages
            let existingIds = Set(messages.map(\.eventId))
            let newMessages = serverMessages.filter { !existingIds.contains($0.eventId) }
            if !newMessages.isEmpty {
                // Replace optimistic placeholders now that real messages arrived
                for msg in messages where msg.eventId.hasPrefix("~optimistic:") {
                    pendingAttachments.removeValue(forKey: msg.eventId)
                }
                messages.removeAll { $0.eventId.hasPrefix("~optimistic:") }
                messages.append(contentsOf: newMessages)
                changed = true
            }

            if changed {
                await sendReadReceiptForLatestMessage()
            }
        } catch {
            // Non-fatal
        }
    }

    private func makeOptimisticMessage(body: String) -> MessageInfo {
        MessageInfo(
            eventId: "~optimistic:\(UUID().uuidString)",
            sender: loggedInUserId ?? "",
            body: body,
            formattedBody: nil,
            messageType: "text",
            timestampMs: UInt64(Date().timeIntervalSince1970 * 1000),
            isEdited: false,
            repliedToEventId: nil,
            mediaSource: nil,
            mediaMimeType: nil,
            mediaWidth: nil,
            mediaHeight: nil,
            mediaSize: nil,
            reactions: []
        )
    }

    public func loadMoreMessages() async {
        guard let client, let roomId = selectedRoomId,
              let token = messageEndToken, !isLoadingMoreMessages else { return }

        isLoadingMoreMessages = true
        do {
            let batch = try await client.messages(roomId: roomId, limit: 50, from: token)
            let existingIds = Set(messages.map(\.eventId))
            let deduped = batch.messages.filter { !existingIds.contains($0.eventId) }
            if deduped.isEmpty {
                hasMoreMessages = false
                messageEndToken = nil
            } else {
                messages.insert(contentsOf: deduped, at: 0)
                messageEndToken = batch.endToken
                hasMoreMessages = batch.endToken != nil
            }
        } catch {
            // Non-fatal
        }
        isLoadingMoreMessages = false
    }

    /// Send a file attachment. Shows an optimistic placeholder while the upload
    /// completes; the placeholder is replaced by the real event on the next sync,
    /// or removed if the upload fails.
    public func sendAttachment(fileURL: URL) async {
        guard let client, let roomId = selectedRoomId else { return }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let filename = fileURL.lastPathComponent
        let mimeType = Self.detectMimeType(for: fileURL)
        let isImage = mimeType.hasPrefix("image/")

        var width: UInt32?
        var height: UInt32?
        if isImage, let image = NSImage(data: data) {
            let size = image.size
            if size.width > 0 { width = UInt32(size.width) }
            if size.height > 0 { height = UInt32(size.height) }
        }

        let placeholder = MessageInfo(
            eventId: "~optimistic:\(UUID().uuidString)",
            sender: loggedInUserId ?? "",
            body: filename,
            formattedBody: nil,
            messageType: isImage ? "image" : "file",
            timestampMs: UInt64(Date().timeIntervalSince1970 * 1000),
            isEdited: false,
            repliedToEventId: nil,
            mediaSource: nil,
            mediaMimeType: mimeType,
            mediaWidth: width,
            mediaHeight: height,
            mediaSize: UInt64(data.count),
            reactions: []
        )
        messages.append(placeholder)
        pendingAttachments[placeholder.eventId] = data

        do {
            try await client.sendAttachment(
                roomId: roomId,
                filename: filename,
                mimeType: mimeType,
                data: data,
                width: width,
                height: height
            )
        } catch {
            messages.removeAll { $0.eventId == placeholder.eventId }
            pendingAttachments.removeValue(forKey: placeholder.eventId)
            errorMessage = error.localizedDescription
        }
    }

    /// Fetch media bytes for the given mxc URI. Checks the in-memory cache first,
    /// then downloads via the client and caches the result.
    public func loadMedia(mxcUri: String) async -> Data? {
        let key = mxcUri as NSString
        if let cached = mediaCache.object(forKey: key) {
            return cached as Data
        }
        guard let client else { return nil }
        do {
            let data = try await client.downloadMedia(mxcUri: mxcUri)
            mediaCache.setObject(data as NSData, forKey: key)
            return data
        } catch {
            return nil
        }
    }

    private static func detectMimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }

    public func sendMessage(body: String) async {
        guard let client, let roomId = selectedRoomId else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let placeholder = makeOptimisticMessage(body: trimmed)
        messages.append(placeholder)

        do {
            try await client.sendMessage(roomId: roomId, body: trimmed)
        } catch {
            messages.removeAll { $0.eventId == placeholder.eventId }
            errorMessage = error.localizedDescription
        }
    }

    public func createRoom(name: String, isPublic: Bool) async {
        guard let client else { return }
        do {
            _ = try await client.createRoom(name: name, isPublic: isPublic)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func fetchPublicRooms() async -> [PublicRoomInfo] {
        guard let client else { return [] }
        do {
            return try await client.publicRooms()
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    public func joinRoom(roomId: String) async {
        guard let client else { return }
        do {
            try await client.joinRoom(roomId: roomId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func fetchRoomMembers(roomId: String) async -> [RoomMemberInfo] {
        guard let client else { return [] }
        do {
            return try await client.roomMembers(roomId: roomId)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    public func leaveRoom(roomId: String) async {
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

    public func sendReply(eventId: String, body: String) async {
        guard let client, let roomId = selectedRoomId else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var placeholder = makeOptimisticMessage(body: trimmed)
        placeholder.repliedToEventId = eventId
        messages.append(placeholder)

        do {
            try await client.sendReply(roomId: roomId, eventId: eventId, body: trimmed)
        } catch {
            messages.removeAll { $0.eventId == placeholder.eventId }
            errorMessage = error.localizedDescription
        }
    }

    public func toggleReaction(eventId: String, key: String) async {
        guard let client, let roomId = selectedRoomId else { return }
        guard let msgIdx = messages.firstIndex(where: { $0.eventId == eventId }) else { return }

        // Check if user already reacted with this key
        let existingReaction = messages[msgIdx].reactions.first(where: {
            $0.key == key && $0.sender == loggedInUserId
        })

        if let existing = existingReaction {
            // Optimistic remove
            messages[msgIdx].reactions.removeAll { $0.eventId == existing.eventId }
            do {
                try await client.redactReaction(roomId: roomId, reactionEventId: existing.eventId)
            } catch {
                // Revert: re-add the reaction
                if let idx = messages.firstIndex(where: { $0.eventId == eventId }) {
                    messages[idx].reactions.append(existing)
                }
                errorMessage = error.localizedDescription
            }
        } else {
            // Optimistic add
            let optimisticReaction = ReactionInfo(
                eventId: "~optimistic:\(UUID().uuidString)",
                key: key,
                sender: loggedInUserId ?? ""
            )
            messages[msgIdx].reactions.append(optimisticReaction)
            do {
                let realEventId = try await client.sendReaction(roomId: roomId, eventId: eventId, key: key)
                // Replace optimistic with real event ID
                if let idx = messages.firstIndex(where: { $0.eventId == eventId }),
                   let rIdx = messages[idx].reactions.firstIndex(where: { $0.eventId == optimisticReaction.eventId }) {
                    messages[idx].reactions[rIdx] = ReactionInfo(
                        eventId: realEventId,
                        key: key,
                        sender: loggedInUserId ?? ""
                    )
                }
            } catch {
                // Revert
                if let idx = messages.firstIndex(where: { $0.eventId == eventId }) {
                    messages[idx].reactions.removeAll { $0.eventId == optimisticReaction.eventId }
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    public func editMessage(eventId: String, newBody: String) async {
        guard let client, let roomId = selectedRoomId else { return }
        guard let idx = messages.firstIndex(where: { $0.eventId == eventId }) else { return }

        let oldBody = messages[idx].body
        let oldFormatted = messages[idx].formattedBody
        let wasEdited = messages[idx].isEdited

        messages[idx].body = newBody
        messages[idx].formattedBody = nil
        messages[idx].isEdited = true

        do {
            try await client.editMessage(roomId: roomId, eventId: eventId, newBody: newBody)
        } catch {
            if let idx = messages.firstIndex(where: { $0.eventId == eventId }) {
                messages[idx].body = oldBody
                messages[idx].formattedBody = oldFormatted
                messages[idx].isEdited = wasEdited
            }
            errorMessage = error.localizedDescription
        }
    }

    public func deleteMessage(eventId: String) async {
        guard let client, let roomId = selectedRoomId else { return }
        guard let idx = messages.firstIndex(where: { $0.eventId == eventId }) else { return }

        let removed = messages.remove(at: idx)

        do {
            try await client.redactMessage(roomId: roomId, eventId: eventId)
        } catch {
            messages.insert(removed, at: min(idx, messages.count))
            errorMessage = error.localizedDescription
        }
    }

    public func sendReadReceipt(roomId: String) async {
        guard let client, let lastMessage = messages.last else { return }
        do {
            try await client.sendReadReceipt(roomId: roomId, eventId: lastMessage.eventId)
        } catch {
            // Non-fatal — read receipts are best-effort
        }
    }

    /// Send a typing notice for the currently selected room. Best-effort.
    public func sendTypingNotice(isTyping: Bool) async {
        guard let client, let roomId = selectedRoomId else { return }
        do {
            try await client.sendTypingNotice(roomId: roomId, isTyping: isTyping)
        } catch {
            // Non-fatal — typing notices are best-effort
        }
    }

    /// Called by SyncUpdateHandler when typing state changes in a room.
    public func handleTypingUpdate(roomId: String, userIds: [String]) {
        let others = userIds.filter { $0 != loggedInUserId }
        typingUsers[roomId] = others
    }

    public func inviteUser(userId: String) async {
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
            // Always check for new messages when a room is selected.
            // Own messages don't increment unreadCount, so we can't gate
            // on that — the dedup in appendNewMessages handles duplicates.
            if appState.selectedRoomId != nil {
                if appState.messages.isEmpty {
                    await appState.refreshMessages()
                } else {
                    await appState.appendNewMessages()
                }
            }
        }
    }

    func onTypingUpdate(roomId: String, userIds: [String]) {
        Task { @MainActor [weak appState] in
            guard let appState else { return }
            appState.handleTypingUpdate(roomId: roomId, userIds: userIds)
        }
    }
}

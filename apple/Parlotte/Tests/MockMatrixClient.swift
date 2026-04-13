import Foundation
import ParlotteSDK

/// A mock MatrixClient for unit testing AppState state transitions.
/// Methods record calls and return configurable results.
///
/// Error injection: set per-method error properties (e.g. `sendMessageError`)
/// for targeted failures, or set `shouldThrow` as a catch-all for any method.
final class MockMatrixClient: MatrixClientProtocol, @unchecked Sendable {
    // MARK: - Call tracking

    var sendMessageCalls: [(roomId: String, body: String)] = []
    var sendReplyCalls: [(roomId: String, eventId: String, body: String)] = []
    var editMessageCalls: [(roomId: String, eventId: String, newBody: String)] = []
    var redactMessageCalls: [(roomId: String, eventId: String)] = []
    var sendReadReceiptCalls: [(roomId: String, eventId: String)] = []
    var sendTypingNoticeCalls: [(roomId: String, isTyping: Bool)] = []
    var sendAttachmentCalls: [(roomId: String, filename: String, mimeType: String, data: Data, width: UInt32?, height: UInt32?)] = []
    var downloadMediaCalls: [String] = []
    var messagesCalls: [(roomId: String, limit: UInt64, from: String?)] = []
    var leaveRoomCalls: [String] = []
    var stopSyncCalls = 0
    var logoutCalls = 0

    // MARK: - Configurable behavior

    var messagesResult: MessageBatch = MessageBatch(messages: [], endToken: nil)
    var roomsResult: [RoomInfo] = []

    /// Catch-all error — thrown by any method if its per-method error is nil.
    var shouldThrow: Error?

    /// Per-method errors — take precedence over shouldThrow.
    var sendMessageError: Error?
    var sendReplyError: Error?
    var editMessageError: Error?
    var redactMessageError: Error?
    var sendReadReceiptError: Error?
    var sendTypingNoticeError: Error?
    var sendAttachmentError: Error?
    var downloadMediaError: Error?
    var downloadMediaResult: Data = Data()
    var messagesError: Error?
    var roomsError: Error?
    var leaveRoomError: Error?

    private func errorFor(_ specific: Error?) throws {
        if let err = specific ?? shouldThrow { throw err }
    }

    // MARK: - MatrixClientProtocol

    func sendMessage(roomId: String, body: String) async throws {
        try errorFor(sendMessageError)
        sendMessageCalls.append((roomId, body))
    }

    func sendReply(roomId: String, eventId: String, body: String) async throws {
        try errorFor(sendReplyError)
        sendReplyCalls.append((roomId, eventId, body))
    }

    func editMessage(roomId: String, eventId: String, newBody: String) async throws {
        try errorFor(editMessageError)
        editMessageCalls.append((roomId, eventId, newBody))
    }

    func redactMessage(roomId: String, eventId: String) async throws {
        try errorFor(redactMessageError)
        redactMessageCalls.append((roomId, eventId))
    }

    func sendReadReceipt(roomId: String, eventId: String) async throws {
        try errorFor(sendReadReceiptError)
        sendReadReceiptCalls.append((roomId, eventId))
    }

    func sendTypingNotice(roomId: String, isTyping: Bool) async throws {
        try errorFor(sendTypingNoticeError)
        sendTypingNoticeCalls.append((roomId, isTyping))
    }

    func sendAttachment(roomId: String, filename: String, mimeType: String, data: Data, width: UInt32?, height: UInt32?) async throws {
        try errorFor(sendAttachmentError)
        sendAttachmentCalls.append((roomId, filename, mimeType, data, width, height))
    }

    func downloadMedia(mxcUri: String) async throws -> Data {
        try errorFor(downloadMediaError)
        downloadMediaCalls.append(mxcUri)
        return downloadMediaResult
    }

    func messages(roomId: String, limit: UInt64, from: String?) async throws -> MessageBatch {
        try errorFor(messagesError)
        messagesCalls.append((roomId, limit, from))
        return messagesResult
    }

    func rooms() async throws -> [RoomInfo] {
        try errorFor(roomsError)
        return roomsResult
    }

    func leaveRoom(roomId: String) async throws {
        try errorFor(leaveRoomError)
        leaveRoomCalls.append(roomId)
    }

    func logout() async throws {
        logoutCalls += 1
    }

    func stopSync() {
        stopSyncCalls += 1
    }

    // MARK: - Stubs (not needed for state management tests)

    func login(username: String, password: String) async throws -> SessionInfo {
        SessionInfo(userId: "@test:example.com", deviceId: "TESTDEV")
    }

    func session() async -> MatrixSessionData? { nil }
    func restoreSession(_ sessionData: MatrixSessionData) async throws {}
    func syncOnce() async throws {}
    func createRoom(name: String, isPublic: Bool) async throws -> String { "!new:example.com" }
    func publicRooms() async throws -> [PublicRoomInfo] { [] }
    func joinRoom(roomId: String) async throws {}
    func roomMembers(roomId: String) async throws -> [RoomMemberInfo] { [] }
    func inviteUser(roomId: String, userId: String) async throws {}
    func loginMethods() async throws -> LoginMethods {
        LoginMethods(supportsPassword: true, supportsSso: false, ssoProviders: [])
    }
    func ssoLoginUrl(redirectUrl: String, idpId: String?) async throws -> String { "" }
    func loginSsoCallback(callbackUrl: String) async throws -> SessionInfo {
        SessionInfo(userId: "@test:example.com", deviceId: "TESTDEV")
    }
    func startSync(listener: ParlotteSyncListener) throws {}
    var isSyncing: Bool { false }
}

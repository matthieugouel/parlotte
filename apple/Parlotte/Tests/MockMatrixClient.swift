import Foundation
import ParlotteSDK

/// A mock MatrixClient for unit testing AppState state transitions.
/// Methods record calls and return configurable results.
final class MockMatrixClient: MatrixClientProtocol, @unchecked Sendable {
    // MARK: - Call tracking

    var sendMessageCalls: [(roomId: String, body: String)] = []
    var sendReplyCalls: [(roomId: String, eventId: String, body: String)] = []
    var editMessageCalls: [(roomId: String, eventId: String, newBody: String)] = []
    var redactMessageCalls: [(roomId: String, eventId: String)] = []
    var sendReadReceiptCalls: [(roomId: String, eventId: String)] = []
    var messagesCalls: [(roomId: String, limit: UInt64, from: String?)] = []

    // MARK: - Configurable behavior

    var messagesResult: MessageBatch = MessageBatch(messages: [], endToken: nil)
    var roomsResult: [RoomInfo] = []
    var shouldThrow: Error?

    // MARK: - MatrixClientProtocol

    func sendMessage(roomId: String, body: String) async throws {
        if let err = shouldThrow { throw err }
        sendMessageCalls.append((roomId, body))
    }

    func sendReply(roomId: String, eventId: String, body: String) async throws {
        if let err = shouldThrow { throw err }
        sendReplyCalls.append((roomId, eventId, body))
    }

    func editMessage(roomId: String, eventId: String, newBody: String) async throws {
        if let err = shouldThrow { throw err }
        editMessageCalls.append((roomId, eventId, newBody))
    }

    func redactMessage(roomId: String, eventId: String) async throws {
        if let err = shouldThrow { throw err }
        redactMessageCalls.append((roomId, eventId))
    }

    func sendReadReceipt(roomId: String, eventId: String) async throws {
        if let err = shouldThrow { throw err }
        sendReadReceiptCalls.append((roomId, eventId))
    }

    func messages(roomId: String, limit: UInt64, from: String?) async throws -> MessageBatch {
        if let err = shouldThrow { throw err }
        messagesCalls.append((roomId, limit, from))
        return messagesResult
    }

    func rooms() async throws -> [RoomInfo] {
        if let err = shouldThrow { throw err }
        return roomsResult
    }

    // MARK: - Stubs (not needed for state management tests)

    func login(username: String, password: String) async throws -> SessionInfo {
        SessionInfo(userId: "@test:example.com", deviceId: "TESTDEV")
    }

    func session() async -> MatrixSessionData? { nil }
    func restoreSession(_ sessionData: MatrixSessionData) async throws {}
    func logout() async throws {}
    func syncOnce() async throws {}
    func createRoom(name: String, isPublic: Bool) async throws -> String { "!new:example.com" }
    func publicRooms() async throws -> [PublicRoomInfo] { [] }
    func joinRoom(roomId: String) async throws {}
    func leaveRoom(roomId: String) async throws {}
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
    func stopSync() {}
    var isSyncing: Bool { false }
}

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
    var sendReactionCalls: [(roomId: String, eventId: String, key: String)] = []
    var redactReactionCalls: [(roomId: String, reactionEventId: String)] = []
    var sendReadReceiptCalls: [(roomId: String, eventId: String)] = []
    var sendTypingNoticeCalls: [(roomId: String, isTyping: Bool)] = []
    var sendAttachmentCalls: [(roomId: String, filename: String, mimeType: String, data: Data, width: UInt32?, height: UInt32?)] = []
    var downloadMediaCalls: [String] = []
    var messagesCalls: [(roomId: String, limit: UInt64, from: String?)] = []
    var leaveRoomCalls: [String] = []
    var inviteUserCalls: [(roomId: String, userId: String)] = []
    var createRoomCalls: [(name: String, isPublic: Bool)] = []
    var publicRoomsCalls = 0
    var stopSyncCalls = 0
    var logoutCalls = 0
    var getProfileCalls = 0
    var setDisplayNameCalls: [String] = []
    var setAvatarCalls: [(mimeType: String, data: Data)] = []
    var removeAvatarCalls = 0
    var roomMembersCalls: [String] = []
    var setRoomNameCalls: [(roomId: String, name: String)] = []
    var setRoomTopicCalls: [(roomId: String, topic: String)] = []

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
    var sendReactionError: Error?
    var sendReactionResult: String = "$reaction:example.com"
    var redactReactionError: Error?
    var sendReadReceiptError: Error?
    var sendTypingNoticeError: Error?
    var sendAttachmentError: Error?
    var downloadMediaError: Error?
    var downloadMediaResult: Data = Data()
    var messagesError: Error?
    var roomsError: Error?
    var leaveRoomError: Error?
    var inviteUserError: Error?
    var createRoomError: Error?
    var createRoomResult: String = "!new:example.com"
    var publicRoomsError: Error?
    var publicRoomsResult: [PublicRoomInfo] = []
    var getProfileError: Error?
    var getProfileResult: UserProfile = UserProfile(displayName: nil, avatarUrl: nil)
    var setDisplayNameError: Error?
    var setAvatarError: Error?
    var setAvatarResult: String = "mxc://example.com/avatar123"
    var removeAvatarError: Error?
    var roomMembersError: Error?
    var roomMembersResult: [RoomMemberInfo] = []
    var setRoomNameError: Error?
    var setRoomTopicError: Error?

    // Recovery
    var recoveryStateResult: RecoveryState = .disabled
    var recoveryStateCalls = 0
    var enableRecoveryCalls: [String?] = []
    var enableRecoveryResult: String = "Es Tb TEST RECOVERY KEY"
    var enableRecoveryError: Error?
    var disableRecoveryCalls = 0
    var disableRecoveryError: Error?
    var recoverCalls: [String] = []
    var recoverError: Error?
    var isLastDeviceResult: Bool? = nil
    var isLastDeviceError: Error?
    var isLastDeviceCalls = 0

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

    func sendReaction(roomId: String, eventId: String, key: String) async throws -> String {
        try errorFor(sendReactionError)
        sendReactionCalls.append((roomId, eventId, key))
        return sendReactionResult
    }

    func redactReaction(roomId: String, reactionEventId: String) async throws {
        try errorFor(redactReactionError)
        redactReactionCalls.append((roomId, reactionEventId))
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

    func getProfile() async throws -> UserProfile {
        try errorFor(getProfileError)
        getProfileCalls += 1
        return getProfileResult
    }

    func setDisplayName(name: String) async throws {
        try errorFor(setDisplayNameError)
        setDisplayNameCalls.append(name)
    }

    func setAvatar(mimeType: String, data: Data) async throws -> String {
        try errorFor(setAvatarError)
        setAvatarCalls.append((mimeType, data))
        return setAvatarResult
    }

    func removeAvatar() async throws {
        try errorFor(removeAvatarError)
        removeAvatarCalls += 1
    }

    func setRoomName(roomId: String, name: String) async throws {
        try errorFor(setRoomNameError)
        setRoomNameCalls.append((roomId, name))
    }

    func setRoomTopic(roomId: String, topic: String) async throws {
        try errorFor(setRoomTopicError)
        setRoomTopicCalls.append((roomId, topic))
    }

    // MARK: - Stubs (not needed for state management tests)

    func login(username: String, password: String) async throws -> SessionInfo {
        SessionInfo(userId: "@test:example.com", deviceId: "TESTDEV")
    }

    func session() async -> MatrixSessionData? { nil }
    func restoreSession(_ sessionData: MatrixSessionData) async throws {}
    func syncOnce() async throws {}
    func createRoom(name: String, isPublic: Bool) async throws -> String {
        try errorFor(createRoomError)
        createRoomCalls.append((name, isPublic))
        return createRoomResult
    }
    func publicRooms() async throws -> [PublicRoomInfo] {
        try errorFor(publicRoomsError)
        publicRoomsCalls += 1
        return publicRoomsResult
    }
    func joinRoom(roomId: String) async throws {}
    func roomMembers(roomId: String) async throws -> [RoomMemberInfo] {
        try errorFor(roomMembersError)
        roomMembersCalls.append(roomId)
        return roomMembersResult
    }
    func inviteUser(roomId: String, userId: String) async throws {
        try errorFor(inviteUserError)
        inviteUserCalls.append((roomId, userId))
    }
    func loginMethods() async throws -> LoginMethods {
        LoginMethods(supportsPassword: true, supportsSso: false, ssoProviders: [])
    }
    func ssoLoginUrl(redirectUrl: String, idpId: String?) async throws -> String { "" }
    func loginSsoCallback(callbackUrl: String) async throws -> SessionInfo {
        SessionInfo(userId: "@test:example.com", deviceId: "TESTDEV")
    }
    func startSync(listener: ParlotteSyncListener) throws {}
    var isSyncing: Bool { false }

    func recoveryState() async -> RecoveryState {
        recoveryStateCalls += 1
        return recoveryStateResult
    }

    func enableRecovery(passphrase: String?) async throws -> String {
        enableRecoveryCalls.append(passphrase)
        try errorFor(enableRecoveryError)
        return enableRecoveryResult
    }

    func disableRecovery() async throws {
        disableRecoveryCalls += 1
        try errorFor(disableRecoveryError)
    }

    func recover(recoveryKey: String) async throws {
        recoverCalls.append(recoveryKey)
        try errorFor(recoverError)
    }

    func isLastDevice() async throws -> Bool? {
        isLastDeviceCalls += 1
        try errorFor(isLastDeviceError)
        return isLastDeviceResult
    }
}

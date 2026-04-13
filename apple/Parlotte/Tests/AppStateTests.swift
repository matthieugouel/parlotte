import Testing
import ParlotteSDK
@testable import ParlotteLib

@MainActor
@Suite("AppState")
struct AppStateTests {
    private var appState: AppState
    private var mock: MockMatrixClient

    init() async {
        mock = MockMatrixClient()
        appState = AppState(profile: "test")
        appState.loggedInUserId = "@alice:example.com"
        appState.selectedRoomId = "!room:example.com"
        appState.client = mock
        // selectedRoomId.didSet spawns a Task (refreshMessages + sendReadReceipt).
        // Await it to prevent it from racing with test bodies.
        await appState.roomRefreshTask?.value
        // Reset call tracking so background setup doesn't pollute test assertions.
        mock.messagesCalls.removeAll()
        mock.sendReadReceiptCalls.removeAll()
    }

    // MARK: - Helpers

    private func makeMessage(
        eventId: String = "$evt1:example.com",
        sender: String = "@bob:example.com",
        body: String = "Hello",
        repliedToEventId: String? = nil,
        reactions: [ReactionInfo] = []
    ) -> MessageInfo {
        MessageInfo(
            eventId: eventId,
            sender: sender,
            body: body,
            formattedBody: nil,
            messageType: "text",
            timestampMs: 1_700_000_000_000,
            isEdited: false,
            repliedToEventId: repliedToEventId,
            mediaSource: nil,
            mediaMimeType: nil,
            mediaWidth: nil,
            mediaHeight: nil,
            mediaSize: nil,
            reactions: reactions
        )
    }

    // MARK: - Send Message

    @Test("Send message appends optimistic placeholder")
    mutating func sendMessageAppendsOptimistically() async {
        await appState.sendMessage(body: "Hello world")

        #expect(appState.messages.count == 1)
        #expect(appState.messages[0].body == "Hello world")
        #expect(appState.messages[0].sender == "@alice:example.com")
        #expect(appState.messages[0].eventId.hasPrefix("~optimistic:"))
    }

    @Test("Send message trims whitespace")
    mutating func sendMessageTrimsWhitespace() async {
        await appState.sendMessage(body: "  spaced  ")

        #expect(mock.sendMessageCalls.count == 1)
        #expect(mock.sendMessageCalls[0].body == "spaced")
    }

    @Test("Send message ignores empty body")
    mutating func sendMessageIgnoresEmpty() async {
        await appState.sendMessage(body: "   ")

        #expect(appState.messages.count == 0)
        #expect(mock.sendMessageCalls.count == 0)
    }

    @Test("Send message removes placeholder on failure")
    mutating func sendMessageRemovesPlaceholderOnFailure() async {
        mock.sendMessageError = ParlotteError.Room(message: "server error")

        await appState.sendMessage(body: "Will fail")

        #expect(appState.messages.count == 0, "Placeholder should be removed on failure")
        #expect(appState.errorMessage != nil)
    }

    @Test("Send message requires selected room")
    mutating func sendMessageRequiresSelectedRoom() async {
        appState.selectedRoomId = nil

        await appState.sendMessage(body: "No room")

        #expect(appState.messages.count == 0)
        #expect(mock.sendMessageCalls.count == 0)
    }

    // MARK: - Send Reply

    @Test("Send reply appends optimistic placeholder with reply ID")
    mutating func sendReplyAppendsOptimisticallyWithReplyId() async {
        let original = makeMessage(eventId: "$original:example.com")
        appState.messages = [original]

        await appState.sendReply(eventId: "$original:example.com", body: "My reply")

        #expect(appState.messages.count == 2)
        let reply = appState.messages[1]
        #expect(reply.body == "My reply")
        #expect(reply.repliedToEventId == "$original:example.com")
        #expect(reply.eventId.hasPrefix("~optimistic:"))
    }

    @Test("Send reply calls server with correct args")
    mutating func sendReplyCallsServerWithCorrectArgs() async {
        await appState.sendReply(eventId: "$evt:x.com", body: "reply text")

        #expect(mock.sendReplyCalls.count == 1)
        #expect(mock.sendReplyCalls[0].roomId == "!room:example.com")
        #expect(mock.sendReplyCalls[0].eventId == "$evt:x.com")
        #expect(mock.sendReplyCalls[0].body == "reply text")
    }

    @Test("Send reply removes placeholder on failure")
    mutating func sendReplyRemovesPlaceholderOnFailure() async {
        mock.sendReplyError = ParlotteError.Room(message: "failed")

        await appState.sendReply(eventId: "$evt:x.com", body: "Will fail")

        #expect(appState.messages.count == 0)
        #expect(appState.errorMessage != nil)
    }

    // MARK: - Edit Message

    @Test("Edit message updates body optimistically")
    mutating func editMessageUpdatesBodyOptimistically() async {
        appState.messages = [makeMessage(eventId: "$e1:x.com", body: "Original")]

        await appState.editMessage(eventId: "$e1:x.com", newBody: "Updated")

        #expect(appState.messages[0].body == "Updated")
        #expect(appState.messages[0].isEdited == true)
        #expect(appState.messages[0].formattedBody == nil)
    }

    @Test("Edit message calls server")
    mutating func editMessageCallsServer() async {
        appState.messages = [makeMessage(eventId: "$e1:x.com", body: "Original")]

        await appState.editMessage(eventId: "$e1:x.com", newBody: "Updated")

        #expect(mock.editMessageCalls.count == 1)
        #expect(mock.editMessageCalls[0].newBody == "Updated")
    }

    @Test("Edit message reverts on failure")
    mutating func editMessageRevertsOnFailure() async {
        let msg = makeMessage(eventId: "$e1:x.com", body: "Original")
        appState.messages = [msg]
        mock.editMessageError = ParlotteError.Room(message: "forbidden")

        await appState.editMessage(eventId: "$e1:x.com", newBody: "Updated")

        #expect(appState.messages[0].body == "Original", "Should revert to original body")
        #expect(appState.messages[0].isEdited == false, "Should revert isEdited flag")
        #expect(appState.errorMessage != nil)
    }

    @Test("Edit nonexistent message is no-op")
    mutating func editNonexistentMessageIsNoOp() async {
        appState.messages = [makeMessage(eventId: "$e1:x.com")]

        await appState.editMessage(eventId: "$nonexistent:x.com", newBody: "Update")

        #expect(mock.editMessageCalls.count == 0)
    }

    // MARK: - Delete Message

    @Test("Delete message removes optimistically")
    mutating func deleteMessageRemovesOptimistically() async {
        appState.messages = [
            makeMessage(eventId: "$e1:x.com", body: "First"),
            makeMessage(eventId: "$e2:x.com", body: "Second"),
        ]

        await appState.deleteMessage(eventId: "$e1:x.com")

        #expect(appState.messages.count == 1)
        #expect(appState.messages[0].eventId == "$e2:x.com")
    }

    @Test("Delete message calls server")
    mutating func deleteMessageCallsServer() async {
        appState.messages = [makeMessage(eventId: "$e1:x.com")]

        await appState.deleteMessage(eventId: "$e1:x.com")

        #expect(mock.redactMessageCalls.count == 1)
        #expect(mock.redactMessageCalls[0].eventId == "$e1:x.com")
    }

    @Test("Delete message reverts on failure")
    mutating func deleteMessageRevertsOnFailure() async {
        appState.messages = [
            makeMessage(eventId: "$e1:x.com", body: "Keep me"),
        ]
        mock.redactMessageError = ParlotteError.Room(message: "forbidden")

        await appState.deleteMessage(eventId: "$e1:x.com")

        #expect(appState.messages.count == 1, "Should revert deletion")
        #expect(appState.messages[0].body == "Keep me")
        #expect(appState.errorMessage != nil)
    }

    @Test("Delete nonexistent message is no-op")
    mutating func deleteNonexistentMessageIsNoOp() async {
        appState.messages = [makeMessage(eventId: "$e1:x.com")]

        await appState.deleteMessage(eventId: "$nonexistent:x.com")

        #expect(appState.messages.count == 1)
        #expect(mock.redactMessageCalls.count == 0)
    }

    // MARK: - Append New Messages (sync handler)

    @Test("Append new messages replaces optimistic placeholders")
    mutating func appendNewMessagesReplacesOptimisticPlaceholders() async {
        appState.messages = [
            makeMessage(eventId: "~optimistic:abc", sender: "@alice:example.com", body: "Hello"),
        ]
        mock.messagesResult = MessageBatch(
            messages: [makeMessage(eventId: "$real:example.com", sender: "@alice:example.com", body: "Hello")],
            endToken: nil
        )

        await appState.appendNewMessages()

        #expect(appState.messages.count == 1)
        #expect(appState.messages[0].eventId == "$real:example.com", "Placeholder should be replaced")
    }

    @Test("Append new messages deduplicates")
    mutating func appendNewMessagesDeduplicates() async {
        let existing = makeMessage(eventId: "$e1:x.com", body: "Exists")
        appState.messages = [existing]
        mock.messagesResult = MessageBatch(messages: [existing], endToken: nil)

        await appState.appendNewMessages()

        #expect(appState.messages.count == 1, "Should not duplicate")
    }

    @Test("Append new messages adds genuinely new ones")
    mutating func appendNewMessagesAddsGenuinelyNew() async {
        appState.messages = [makeMessage(eventId: "$e1:x.com", body: "Old")]
        mock.messagesResult = MessageBatch(
            messages: [
                makeMessage(eventId: "$e1:x.com", body: "Old"),
                makeMessage(eventId: "$e2:x.com", body: "New"),
            ],
            endToken: nil
        )

        await appState.appendNewMessages()

        #expect(appState.messages.count == 2)
        #expect(appState.messages[1].body == "New")
    }

    @Test("Append new messages picks up edits")
    mutating func appendNewMessagesPicksUpEdits() async {
        appState.messages = [makeMessage(eventId: "$e1:x.com", body: "Original")]
        mock.messagesResult = MessageBatch(
            messages: [
                MessageInfo(
                    eventId: "$e1:x.com", sender: "@bob:example.com",
                    body: "Edited", formattedBody: nil, messageType: "text",
                    timestampMs: 1_700_000_000_000, isEdited: true, repliedToEventId: nil,
                    mediaSource: nil, mediaMimeType: nil, mediaWidth: nil, mediaHeight: nil, mediaSize: nil,
                    reactions: []
                ),
            ],
            endToken: nil
        )

        await appState.appendNewMessages()

        #expect(appState.messages.count == 1)
        #expect(appState.messages[0].body == "Edited")
        #expect(appState.messages[0].isEdited == true)
    }

    @Test("Append new messages removes redacted messages")
    mutating func appendNewMessagesRemovesRedacted() async {
        appState.messages = [
            makeMessage(eventId: "$e1:x.com", body: "Keep"),
            makeMessage(eventId: "$e2:x.com", body: "Redacted"),
        ]
        // Server only returns the non-redacted message
        mock.messagesResult = MessageBatch(
            messages: [makeMessage(eventId: "$e1:x.com", body: "Keep")],
            endToken: nil
        )

        await appState.appendNewMessages()

        #expect(appState.messages.count == 1)
        #expect(appState.messages[0].eventId == "$e1:x.com")
    }

    @Test("Append new messages preserves optimistic placeholders when server has not confirmed")
    mutating func appendNewMessagesPreservesOptimisticBeforeConfirmation() async {
        appState.messages = [
            makeMessage(eventId: "$e1:x.com", body: "Old"),
            MessageInfo(
                eventId: "~optimistic:abc", sender: "@alice:example.com",
                body: "Sending...", formattedBody: nil, messageType: "text",
                timestampMs: 1_700_000_001_000, isEdited: false, repliedToEventId: nil,
                mediaSource: nil, mediaMimeType: nil, mediaWidth: nil, mediaHeight: nil, mediaSize: nil,
                reactions: []
            ),
        ]
        // Server returns the old message but not the optimistic one yet
        mock.messagesResult = MessageBatch(
            messages: [makeMessage(eventId: "$e1:x.com", body: "Old")],
            endToken: nil
        )

        await appState.appendNewMessages()

        #expect(appState.messages.count == 2, "Optimistic placeholder should be preserved")
        #expect(appState.messages[1].eventId == "~optimistic:abc")
    }

    @Test("Append new messages does not mutate array when nothing changed")
    mutating func appendNewMessagesNoMutationWhenUnchanged() async {
        let msg = makeMessage(eventId: "$e1:x.com", body: "Same")
        appState.messages = [msg]
        mock.messagesResult = MessageBatch(messages: [msg], endToken: nil)

        await appState.appendNewMessages()

        #expect(appState.messages.count == 1)
        #expect(appState.messages[0].body == "Same")
    }

    @Test("Append new messages skips when messages is empty")
    mutating func appendNewMessagesSkipsWhenEmpty() async {
        appState.messages = []
        mock.messagesResult = MessageBatch(
            messages: [makeMessage(eventId: "$e1:x.com", body: "Server msg")],
            endToken: nil
        )

        await appState.appendNewMessages()

        #expect(appState.messages.isEmpty, "Should bail early when messages is empty")
        #expect(mock.messagesCalls.isEmpty, "Should not call server")
    }

    @Test("Sync with empty messages falls back to refreshMessages")
    mutating func syncWithEmptyMessagesFallsBackToRefresh() async {
        appState.messages = []
        mock.messagesResult = MessageBatch(
            messages: [makeMessage(eventId: "$e1:x.com", body: "History")],
            endToken: nil
        )

        // Simulate what the sync handler does
        if appState.messages.isEmpty {
            await appState.refreshMessages()
        } else {
            await appState.appendNewMessages()
        }

        #expect(appState.messages.count == 1)
        #expect(appState.messages[0].body == "History")
    }

    // MARK: - Message Pagination

    @Test("Load more messages prepends older messages")
    mutating func loadMoreMessagesPrepends() async {
        appState.messages = [makeMessage(eventId: "$e3:x.com", body: "Latest")]
        appState.hasMoreMessages = true
        mock.messagesResult = MessageBatch(
            messages: [makeMessage(eventId: "$e3:x.com", body: "Latest")],
            endToken: "token123"
        )
        await appState.refreshMessages()

        mock.messagesResult = MessageBatch(
            messages: [makeMessage(eventId: "$e1:x.com", body: "Oldest")],
            endToken: "token456"
        )
        await appState.loadMoreMessages()

        #expect(appState.messages.count == 2)
        #expect(appState.messages[0].body == "Oldest")
        #expect(appState.messages[1].body == "Latest")
    }

    // MARK: - Room Selection

    @Test("Selecting room clears messages")
    mutating func selectingRoomClearsMessages() {
        appState.messages = [makeMessage()]
        appState.hasMoreMessages = true

        appState.selectedRoomId = "!other:example.com"

        #expect(appState.messages.isEmpty)
        #expect(appState.hasMoreMessages == false)
    }

    @Test("Selecting nil room clears messages")
    mutating func selectingNilRoomClearsMessages() {
        appState.messages = [makeMessage()]

        appState.selectedRoomId = nil

        #expect(appState.messages.isEmpty)
    }

    // MARK: - Refresh Rooms

    @Test("Refresh rooms updates room list")
    mutating func refreshRoomsUpdatesRoomList() async {
        mock.roomsResult = [
            RoomInfo(id: "!a:x.com", displayName: "Alpha", isEncrypted: false, isPublic: false, topic: nil, isInvited: false, unreadCount: 0),
        ]

        await appState.refreshRooms()

        #expect(appState.rooms.count == 1)
        #expect(appState.rooms[0].displayName == "Alpha")
    }

    @Test("Refresh rooms zeroes unread count on selected room")
    mutating func refreshRoomsZeroesUnreadOnSelectedRoom() async {
        appState.selectedRoomId = "!a:x.com"
        mock.roomsResult = [
            RoomInfo(id: "!a:x.com", displayName: "Selected", isEncrypted: false, isPublic: false, topic: nil, isInvited: false, unreadCount: 5),
            RoomInfo(id: "!b:x.com", displayName: "Other", isEncrypted: false, isPublic: false, topic: nil, isInvited: false, unreadCount: 3),
        ]

        let hasNew = await appState.refreshRooms()

        #expect(hasNew == true, "Should report new messages in selected room")
        #expect(appState.rooms[0].unreadCount == 0, "Selected room unread should be zeroed")
        #expect(appState.rooms[1].unreadCount == 3, "Other room unread should be preserved")
    }

    @Test("Refresh rooms returns false when no unread in selected room")
    mutating func refreshRoomsReturnsFalseWhenNoUnread() async {
        appState.selectedRoomId = "!a:x.com"
        mock.roomsResult = [
            RoomInfo(id: "!a:x.com", displayName: "Selected", isEncrypted: false, isPublic: false, topic: nil, isInvited: false, unreadCount: 0),
        ]

        let hasNew = await appState.refreshRooms()

        #expect(hasNew == false)
    }

    @Test("Refresh rooms sets error on failure")
    mutating func refreshRoomsSetsErrorOnFailure() async {
        mock.roomsError = ParlotteError.Room(message: "forbidden")

        let hasNew = await appState.refreshRooms()

        #expect(hasNew == false)
        #expect(appState.errorMessage != nil)
    }

    // MARK: - Leave Room

    @Test("Leave selected room clears selection")
    mutating func leaveSelectedRoomClearsSelection() async {
        appState.selectedRoomId = "!room:example.com"

        await appState.leaveRoom(roomId: "!room:example.com")

        #expect(appState.selectedRoomId == nil)
        #expect(mock.leaveRoomCalls.count == 1)
    }

    @Test("Leave non-selected room preserves selection")
    mutating func leaveNonSelectedRoomPreservesSelection() async {
        appState.selectedRoomId = "!room:example.com"

        await appState.leaveRoom(roomId: "!other:example.com")

        #expect(appState.selectedRoomId == "!room:example.com")
        #expect(mock.leaveRoomCalls.count == 1)
    }

    @Test("Leave room sets error on failure")
    mutating func leaveRoomSetsErrorOnFailure() async {
        mock.leaveRoomError = ParlotteError.Room(message: "forbidden")

        await appState.leaveRoom(roomId: "!room:example.com")

        #expect(appState.errorMessage != nil)
        #expect(appState.selectedRoomId == "!room:example.com", "Selection should not change on failure")
    }

    // MARK: - Logout

    @Test("Logout resets all state")
    mutating func logoutResetsAllState() async {
        appState.isLoggedIn = true
        appState.loggedInUserId = "@alice:example.com"
        appState.isSyncActive = true
        appState.rooms = [
            RoomInfo(id: "!a:x.com", displayName: "Room", isEncrypted: false, isPublic: false, topic: nil, isInvited: false, unreadCount: 0),
        ]
        appState.messages = [makeMessage()]

        await appState.logout()

        #expect(appState.isLoggedIn == false)
        #expect(appState.loggedInUserId == nil)
        #expect(appState.isSyncActive == false)
        #expect(appState.rooms.isEmpty)
        #expect(appState.typingUsers.isEmpty)
        #expect(appState.selectedRoomId == nil)
        #expect(appState.messages.isEmpty)
        #expect(appState.client == nil)
    }

    @Test("Logout stops sync and calls server")
    mutating func logoutStopsSyncAndCallsServer() async {
        appState.isSyncActive = true

        await appState.logout()

        #expect(mock.stopSyncCalls == 1)
        #expect(mock.logoutCalls == 1)
    }

    // MARK: - Typing Indicators

    @Test("Typing update filters out own user")
    mutating func handleTypingUpdateFiltersOwnUser() {
        appState.handleTypingUpdate(
            roomId: "!room:example.com",
            userIds: ["@alice:example.com", "@bob:example.com", "@carol:example.com"]
        )

        let typing = appState.typingUsers["!room:example.com"]
        #expect(typing == ["@bob:example.com", "@carol:example.com"])
    }

    @Test("Typing update replaces previous state")
    mutating func handleTypingUpdateReplacesState() {
        appState.handleTypingUpdate(roomId: "!room:example.com", userIds: ["@bob:example.com"])
        appState.handleTypingUpdate(roomId: "!room:example.com", userIds: ["@carol:example.com"])

        let typing = appState.typingUsers["!room:example.com"]
        #expect(typing == ["@carol:example.com"])
    }

    @Test("currentRoomTypingUsers returns selected room's typing users")
    mutating func currentRoomTypingUsersReturnsSelectedRoom() {
        appState.handleTypingUpdate(roomId: "!room:example.com", userIds: ["@bob:example.com"])
        appState.handleTypingUpdate(roomId: "!other:example.com", userIds: ["@carol:example.com"])

        #expect(appState.currentRoomTypingUsers == ["@bob:example.com"])
    }

    @Test("currentRoomTypingUsers empty when no room selected")
    mutating func currentRoomTypingUsersEmptyWhenNoRoom() {
        appState.selectedRoomId = nil
        appState.handleTypingUpdate(roomId: "!room:example.com", userIds: ["@bob:example.com"])

        #expect(appState.currentRoomTypingUsers.isEmpty)
    }

    @Test("Empty typing update clears state for room")
    mutating func emptyTypingUpdateClearsState() {
        appState.handleTypingUpdate(roomId: "!room:example.com", userIds: ["@bob:example.com"])
        appState.handleTypingUpdate(roomId: "!room:example.com", userIds: [])

        #expect(appState.currentRoomTypingUsers.isEmpty)
    }

    @Test("Logout clears typing state")
    mutating func logoutClearsTypingState() async {
        appState.handleTypingUpdate(roomId: "!room:example.com", userIds: ["@bob:example.com"])

        await appState.logout()

        #expect(appState.typingUsers.isEmpty)
    }

    @Test("Send typing notice calls client")
    mutating func sendTypingNoticeCallsClient() async {
        await appState.sendTypingNotice(isTyping: true)

        #expect(mock.sendTypingNoticeCalls.count == 1)
        #expect(mock.sendTypingNoticeCalls[0].roomId == "!room:example.com")
        #expect(mock.sendTypingNoticeCalls[0].isTyping == true)
    }

    @Test("Send typing notice requires selected room")
    mutating func sendTypingNoticeRequiresSelectedRoom() async {
        appState.selectedRoomId = nil

        await appState.sendTypingNotice(isTyping: true)

        #expect(mock.sendTypingNoticeCalls.isEmpty)
    }

    @Test("Send typing notice is best-effort")
    mutating func sendTypingNoticeIsBestEffort() async {
        mock.sendTypingNoticeError = ParlotteError.Room(message: "network error")

        await appState.sendTypingNotice(isTyping: true)

        #expect(appState.errorMessage == nil, "Typing notice errors should be swallowed")
    }

    // MARK: - Attachments

    @Test("Send attachment appends optimistic placeholder with media fields")
    mutating func sendAttachmentAppendsOptimistically() async {
        let data = MediaTestHelpers.pngMagicBytes()
        let url = MediaTestHelpers.makeTempFile(name: "photo.png", contents: data)
        defer { MediaTestHelpers.removeTempFile(at: url) }

        await appState.sendAttachment(fileURL: url)

        #expect(appState.messages.count == 1)
        let msg = appState.messages[0]
        #expect(msg.eventId.hasPrefix("~optimistic:"))
        #expect(msg.messageType == "image")
        #expect(msg.body == "photo.png")
        #expect(msg.mediaMimeType == "image/png")
        #expect(msg.mediaSize == UInt64(data.count))
        #expect(appState.pendingAttachments[msg.eventId] == data)
    }

    @Test("Send attachment classifies non-image as file")
    mutating func sendAttachmentClassifiesNonImageAsFile() async {
        let data = MediaTestHelpers.stringBytes("hello")
        let url = MediaTestHelpers.makeTempFile(name: "notes.txt", contents: data)
        defer { MediaTestHelpers.removeTempFile(at: url) }

        await appState.sendAttachment(fileURL: url)

        #expect(appState.messages.count == 1)
        #expect(appState.messages[0].messageType == "file")
    }

    @Test("Send attachment removes placeholder and clears pending on failure")
    mutating func sendAttachmentRemovesPlaceholderOnFailure() async {
        mock.sendAttachmentError = ParlotteError.Room(message: "upload failed")
        let url = MediaTestHelpers.makeTempFile(name: "fail.bin", contents: MediaTestHelpers.bytes([0x00]))
        defer { MediaTestHelpers.removeTempFile(at: url) }

        await appState.sendAttachment(fileURL: url)

        #expect(appState.messages.isEmpty)
        #expect(appState.pendingAttachments.isEmpty)
        #expect(appState.errorMessage != nil)
    }

    @Test("Send attachment calls client with correct args")
    mutating func sendAttachmentCallsClientWithArgs() async {
        let data = MediaTestHelpers.stringBytes("pdf bytes")
        let url = MediaTestHelpers.makeTempFile(name: "doc.pdf", contents: data)
        defer { MediaTestHelpers.removeTempFile(at: url) }

        await appState.sendAttachment(fileURL: url)

        #expect(mock.sendAttachmentCalls.count == 1)
        let call = mock.sendAttachmentCalls[0]
        #expect(call.roomId == "!room:example.com")
        #expect(call.filename == "doc.pdf")
        #expect(call.mimeType == "application/pdf")
        #expect(call.data == data)
    }

    @Test("Send attachment requires selected room")
    mutating func sendAttachmentRequiresSelectedRoom() async {
        appState.selectedRoomId = nil
        let url = MediaTestHelpers.makeTempFile(name: "x.txt", contents: MediaTestHelpers.stringBytes("x"))
        defer { MediaTestHelpers.removeTempFile(at: url) }

        await appState.sendAttachment(fileURL: url)

        #expect(mock.sendAttachmentCalls.isEmpty)
    }

    @Test("Load media caches downloaded bytes")
    mutating func loadMediaCachesBytes() async {
        let bytes = MediaTestHelpers.stringBytes("image-bytes")
        mock.downloadMediaResult = bytes

        let first = await appState.loadMedia(mxcUri: "mxc://a/1")
        let second = await appState.loadMedia(mxcUri: "mxc://a/1")

        #expect(first == bytes)
        #expect(second == bytes)
        #expect(mock.downloadMediaCalls.count == 1, "second call should hit cache")
    }

    @Test("Load media returns nil on error")
    mutating func loadMediaReturnsNilOnError() async {
        mock.downloadMediaError = ParlotteError.Network(message: "unreachable")

        let result = await appState.loadMedia(mxcUri: "mxc://a/1")

        #expect(result == nil)
    }

    @Test("Append new messages drops pending attachments for replaced placeholders")
    mutating func appendNewMessagesClearsPendingAttachments() async {
        let url = MediaTestHelpers.makeTempFile(name: "img.png", contents: MediaTestHelpers.bytes([0xFF]))
        defer { MediaTestHelpers.removeTempFile(at: url) }

        await appState.sendAttachment(fileURL: url)
        #expect(appState.pendingAttachments.count == 1)

        // Server confirms with a real event.
        let realMsg = makeMessage(eventId: "$real:x.com", sender: "@alice:example.com", body: "img.png")
        mock.messagesResult = MessageBatch(messages: [realMsg], endToken: nil)

        await appState.appendNewMessages()

        #expect(appState.pendingAttachments.isEmpty)
        #expect(!appState.messages.contains { $0.eventId.hasPrefix("~optimistic:") })
    }

    @Test("Logout clears pending attachments")
    mutating func logoutClearsMediaState() async {
        appState.pendingAttachments["~optimistic:foo"] = MediaTestHelpers.bytes([0x42])

        await appState.logout()

        #expect(appState.pendingAttachments.isEmpty)
    }

    // MARK: - Reactions

    @Test("Toggle reaction adds optimistic reaction")
    mutating func toggleReactionAddsOptimistically() async {
        let msg = makeMessage()
        appState.messages = [msg]

        await appState.toggleReaction(eventId: msg.eventId, key: "\u{1f44d}")

        #expect(appState.messages[0].reactions.count == 1)
        #expect(appState.messages[0].reactions[0].key == "\u{1f44d}")
        #expect(appState.messages[0].reactions[0].sender == "@alice:example.com")
        // Optimistic ID should be replaced with real one
        #expect(appState.messages[0].reactions[0].eventId == "$reaction:example.com")
    }

    @Test("Toggle reaction calls client with correct args")
    mutating func toggleReactionCallsClient() async {
        let msg = makeMessage()
        appState.messages = [msg]

        await appState.toggleReaction(eventId: msg.eventId, key: "\u{1f44d}")

        #expect(mock.sendReactionCalls.count == 1)
        #expect(mock.sendReactionCalls[0].roomId == "!room:example.com")
        #expect(mock.sendReactionCalls[0].eventId == msg.eventId)
        #expect(mock.sendReactionCalls[0].key == "\u{1f44d}")
    }

    @Test("Toggle reaction removes own existing reaction")
    mutating func toggleReactionRemovesOwn() async {
        let reaction = ReactionInfo(
            eventId: "$r1:example.com",
            key: "\u{1f44d}",
            sender: "@alice:example.com"
        )
        let msg = makeMessage(reactions: [reaction])
        appState.messages = [msg]

        await appState.toggleReaction(eventId: msg.eventId, key: "\u{1f44d}")

        #expect(appState.messages[0].reactions.isEmpty)
        #expect(mock.redactReactionCalls.count == 1)
        #expect(mock.redactReactionCalls[0].reactionEventId == "$r1:example.com")
    }

    @Test("Toggle reaction failure reverts optimistic add")
    mutating func toggleReactionRevertsAddOnFailure() async {
        mock.sendReactionError = ParlotteError.Room(message: "failed")
        let msg = makeMessage()
        appState.messages = [msg]

        await appState.toggleReaction(eventId: msg.eventId, key: "\u{1f44d}")

        #expect(appState.messages[0].reactions.isEmpty)
        #expect(appState.errorMessage != nil)
    }

    @Test("Toggle reaction failure reverts optimistic remove")
    mutating func toggleReactionRevertsRemoveOnFailure() async {
        mock.redactReactionError = ParlotteError.Room(message: "failed")
        let reaction = ReactionInfo(
            eventId: "$r1:example.com",
            key: "\u{1f44d}",
            sender: "@alice:example.com"
        )
        let msg = makeMessage(reactions: [reaction])
        appState.messages = [msg]

        await appState.toggleReaction(eventId: msg.eventId, key: "\u{1f44d}")

        #expect(appState.messages[0].reactions.count == 1)
        #expect(appState.messages[0].reactions[0].eventId == "$r1:example.com")
        #expect(appState.errorMessage != nil)
    }

    @Test("Toggle reaction requires selected room")
    mutating func toggleReactionRequiresSelectedRoom() async {
        appState.selectedRoomId = nil
        let msg = makeMessage()
        appState.messages = [msg]

        await appState.toggleReaction(eventId: msg.eventId, key: "\u{1f44d}")

        #expect(mock.sendReactionCalls.isEmpty)
    }
}

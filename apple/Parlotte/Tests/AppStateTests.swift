import Testing
import ParlotteSDK
@testable import ParlotteLib

@MainActor
@Suite("AppState")
struct AppStateTests {
    private var appState: AppState
    private var mock: MockMatrixClient

    init() {
        mock = MockMatrixClient()
        appState = AppState(profile: "test")
        appState.client = mock
        appState.loggedInUserId = "@alice:example.com"
        appState.selectedRoomId = "!room:example.com"
    }

    // MARK: - Helpers

    private func makeMessage(
        eventId: String = "$evt1:example.com",
        sender: String = "@bob:example.com",
        body: String = "Hello",
        repliedToEventId: String? = nil
    ) -> MessageInfo {
        MessageInfo(
            eventId: eventId,
            sender: sender,
            body: body,
            formattedBody: nil,
            messageType: "text",
            timestampMs: 1_700_000_000_000,
            isEdited: false,
            repliedToEventId: repliedToEventId
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
}

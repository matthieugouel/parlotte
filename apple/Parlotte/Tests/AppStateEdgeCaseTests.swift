import Testing
import ParlotteSDK
@testable import ParlotteLib

/// Targeted edge-case coverage for AppState regression vectors not exercised
/// by the main AppStateTests suite (pagination concurrency, reaction on
/// missing message, invite/create/public-rooms error paths, delete revert
/// position).
@MainActor
@Suite("AppState edge cases")
struct AppStateEdgeCaseTests {
    private var appState: AppState
    private var mock: MockMatrixClient

    init() async {
        mock = MockMatrixClient()
        appState = AppState(profile: "edge-test")
        appState.loggedInUserId = "@alice:example.com"
        appState.selectedRoomId = "!room:example.com"
        appState.client = mock
        await appState.roomRefreshTask?.value
        mock.messagesCalls.removeAll()
        mock.sendReadReceiptCalls.removeAll()
    }

    // MARK: - Helpers

    private func makeMessage(
        eventId: String = "$evt:example.com",
        sender: String = "@bob:example.com",
        body: String = "Hello",
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
            repliedToEventId: nil,
            mediaSource: nil,
            mediaMimeType: nil,
            mediaWidth: nil,
            mediaHeight: nil,
            mediaSize: nil,
            reactions: reactions
        )
    }

    /// Seed a valid end-token so loadMoreMessages proceeds past the guard.
    /// Uses the pagination path: initial messages() call returns endToken.
    private mutating func seedEndToken(_ token: String = "tok-1") async {
        mock.messagesResult = MessageBatch(
            messages: [makeMessage(eventId: "$seed:example.com")],
            endToken: token
        )
        await appState.refreshMessages()
        mock.messagesCalls.removeAll()
    }

    // MARK: - loadMoreMessages

    @Test("loadMoreMessages clears isLoadingMoreMessages after an error")
    mutating func loadMoreMessagesErrorClearsLoadingFlag() async {
        await seedEndToken()
        mock.messagesError = ParlotteError.Network(message: "boom")

        await appState.loadMoreMessages()

        #expect(appState.isLoadingMoreMessages == false)
    }

    @Test("loadMoreMessages bails while another load is in flight")
    mutating func loadMoreMessagesConcurrencyGuard() async {
        await seedEndToken()
        appState.isLoadingMoreMessages = true

        await appState.loadMoreMessages()

        // Guard should prevent any network call.
        #expect(mock.messagesCalls.isEmpty)
        // We only set the flag, never cleared it — the method must not have
        // touched it (no isLoadingMoreMessages = false side-effect).
        #expect(appState.isLoadingMoreMessages == true)
    }

    @Test("loadMoreMessages clears pagination state when every older message is a duplicate")
    mutating func loadMoreMessagesAllDuplicates() async {
        await seedEndToken()
        // Server returns the same seed message back — all duplicates.
        mock.messagesResult = MessageBatch(
            messages: [makeMessage(eventId: "$seed:example.com")],
            endToken: "tok-2"
        )

        await appState.loadMoreMessages()

        #expect(appState.hasMoreMessages == false)
        // Implementation sets messageEndToken = nil; verify by checking that
        // a second call is now a no-op (the guard fires on nil token).
        mock.messagesCalls.removeAll()
        await appState.loadMoreMessages()
        #expect(mock.messagesCalls.isEmpty)
    }

    // MARK: - toggleReaction

    @Test("toggleReaction on a nonexistent message is a no-op")
    mutating func toggleReactionMissingMessage() async {
        appState.messages = [makeMessage(eventId: "$known:example.com")]
        mock.sendReactionCalls.removeAll()

        await appState.toggleReaction(eventId: "$nonexistent:example.com", key: "👍")

        #expect(mock.sendReactionCalls.isEmpty)
        #expect(mock.redactReactionCalls.isEmpty)
        #expect(appState.messages[0].reactions.isEmpty)
        #expect(appState.errorMessage == nil)
    }

    // MARK: - inviteUser

    @Test("inviteUser forwards roomId and userId to the client")
    mutating func inviteUserCallsClient() async {
        await appState.inviteUser(userId: "@bob:example.com")

        #expect(mock.inviteUserCalls.count == 1)
        #expect(mock.inviteUserCalls[0].roomId == "!room:example.com")
        #expect(mock.inviteUserCalls[0].userId == "@bob:example.com")
    }

    @Test("inviteUser is a no-op without a selected room")
    mutating func inviteUserRequiresRoom() async {
        appState.selectedRoomId = nil
        mock.inviteUserCalls.removeAll()

        await appState.inviteUser(userId: "@bob:example.com")

        #expect(mock.inviteUserCalls.isEmpty)
    }

    @Test("inviteUser surfaces server errors via errorMessage")
    mutating func inviteUserSurfacesError() async {
        mock.inviteUserError = ParlotteError.Room(message: "forbidden")

        await appState.inviteUser(userId: "@bob:example.com")

        #expect(appState.errorMessage != nil)
    }

    // MARK: - createRoom

    @Test("createRoom surfaces server errors via errorMessage")
    mutating func createRoomSurfacesError() async {
        mock.createRoomError = ParlotteError.Room(message: "forbidden")

        await appState.createRoom(name: "nope", isPublic: true)

        #expect(appState.errorMessage != nil)
    }

    // MARK: - fetchPublicRooms

    @Test("fetchPublicRooms returns [] and sets errorMessage on failure")
    mutating func fetchPublicRoomsError() async {
        mock.publicRoomsError = ParlotteError.Network(message: "unreachable")

        let result = await appState.fetchPublicRooms()

        #expect(result.isEmpty)
        #expect(appState.errorMessage != nil)
    }

    // MARK: - deleteMessage revert

    @Test("deleteMessage revert restores the message at its original index")
    mutating func deleteMessageRevertPreservesPosition() async {
        appState.messages = [
            makeMessage(eventId: "$a:example.com", body: "first"),
            makeMessage(eventId: "$b:example.com", body: "middle"),
            makeMessage(eventId: "$c:example.com", body: "last"),
        ]
        mock.redactMessageError = ParlotteError.Room(message: "forbidden")

        await appState.deleteMessage(eventId: "$b:example.com")

        #expect(appState.messages.count == 3)
        #expect(appState.messages[0].eventId == "$a:example.com")
        #expect(appState.messages[1].eventId == "$b:example.com")
        #expect(appState.messages[2].eventId == "$c:example.com")
        #expect(appState.errorMessage != nil)
    }
}

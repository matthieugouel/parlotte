import Foundation
import Network
import ParlotteSDK

/// Local-only JSON IPC server for AI-driven UI testing.
///
/// Exposes two endpoints on `127.0.0.1`:
/// - `GET /state` — snapshot of `AppState` as JSON
/// - `POST /cmd`  — invoke a command (`{"op": "...", ...args}`) against `AppState`
///
/// Intended to be opt-in via the `--debug-ipc-port` CLI flag. Not suitable for
/// production. Binds to the loopback interface only.
public final class DebugServer: @unchecked Sendable {
    private let appState: AppState
    private let queue = DispatchQueue(label: "parlotte.debug-ipc")
    private var listener: NWListener?

    public init(appState: AppState) {
        self.appState = appState
    }

    /// Start listening on `127.0.0.1:port`. Pass `0` for an OS-assigned port.
    /// Returns the actual port once the listener is ready.
    @discardableResult
    public func start(port: UInt16) throws -> UInt16 {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Restrict to the loopback interface — no external access.
        params.requiredInterfaceType = .loopback

        let listener: NWListener
        if port == 0 {
            listener = try NWListener(using: params)
        } else {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                throw DebugServerError.invalidPort(port)
            }
            listener = try NWListener(using: params, on: nwPort)
        }
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var readyPort: UInt16 = 0
        nonisolated(unsafe) var listenerError: Error?

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                readyPort = listener.port?.rawValue ?? port
                semaphore.signal()
            case .failed(let error):
                listenerError = error
                semaphore.signal()
            default:
                break
            }
        }

        listener.start(queue: queue)
        semaphore.wait()

        if let err = listenerError {
            throw err
        }
        return readyPort
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, accumulated: Data())
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }

            if error != nil {
                connection.cancel()
                return
            }

            var buffer = accumulated
            if let data { buffer.append(data) }

            if let request = Self.parseRequest(buffer) {
                self.dispatch(request: request, connection: connection)
                return
            }

            if isComplete {
                self.respond(connection, status: 400, body: Data("bad request\n".utf8))
                return
            }

            // Haven't seen the full request yet — read more.
            self.receive(connection, accumulated: buffer)
        }
    }

    private func dispatch(request: HTTPRequest, connection: NWConnection) {
        Task { [weak self] in
            guard let self else { connection.cancel(); return }
            let (status, body) = await self.handle(request)
            self.respond(connection, status: status, body: body)
        }
    }

    private func respond(_ connection: NWConnection, status: Int, body: Data) {
        let reason = Self.reasonPhrase(for: status)
        let header =
            "HTTP/1.1 \(status) \(reason)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n"
            + "\r\n"
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Routing

    private func handle(_ request: HTTPRequest) async -> (Int, Data) {
        switch (request.method, request.path) {
        case ("GET", "/state"):
            let snapshot = await MainActor.run { DebugSnapshot.from(appState: self.appState) }
            return encode(snapshot)

        case ("POST", "/cmd"):
            return await handleCommand(body: request.body)

        default:
            return (404, Self.errorBody("not found"))
        }
    }

    private func handleCommand(body: Data) async -> (Int, Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let op = obj["op"] as? String else {
            return (400, Self.errorBody("invalid command: expected JSON object with \"op\""))
        }

        switch op {
        case "select_room":
            return await cmdSelectRoom(args: obj)
        case "send_message":
            return await cmdSendMessage(args: obj)
        case "load_older":
            return await cmdLoadOlder()
        case "refresh":
            return await cmdRefresh()
        case "logout":
            return await cmdLogout()
        default:
            return (400, Self.errorBody("unknown op: \(op)"))
        }
    }

    // MARK: - Commands

    private func cmdSelectRoom(args: [String: Any]) async -> (Int, Data) {
        let targetId: String? = await MainActor.run {
            if let id = args["id"] as? String { return id }
            if let name = args["name"] as? String {
                return self.appState.rooms.first(where: { $0.displayName == name })?.id
            }
            return nil
        }

        guard let roomId = targetId else {
            return (404, Self.errorBody("room not found (provide \"id\" or \"name\")"))
        }

        let refreshTask: Task<Void, Never>? = await MainActor.run {
            self.appState.selectedRoomId = roomId
            return self.appState.roomRefreshTask
        }
        await refreshTask?.value
        return okResponse(["selectedRoomId": roomId])
    }

    private func cmdSendMessage(args: [String: Any]) async -> (Int, Data) {
        guard let body = args["body"] as? String else {
            return (400, Self.errorBody("missing \"body\""))
        }
        await appState.sendMessage(body: body)
        return okResponse([:])
    }

    private func cmdLoadOlder() async -> (Int, Data) {
        await appState.loadMoreMessages()
        return okResponse([:])
    }

    private func cmdRefresh() async -> (Int, Data) {
        await appState.refreshRooms()
        let hasRoom = await MainActor.run { appState.selectedRoomId != nil }
        if hasRoom {
            await appState.refreshMessages()
        }
        return okResponse([:])
    }

    private func cmdLogout() async -> (Int, Data) {
        await appState.logout()
        return okResponse([:])
    }

    // MARK: - Helpers

    private func encode<T: Encodable>(_ value: T) -> (Int, Data) {
        do {
            let data = try JSONEncoder.debug.encode(value)
            return (200, data)
        } catch {
            return (500, Self.errorBody("encode failed: \(error)"))
        }
    }

    private func okResponse(_ extra: [String: Any]) -> (Int, Data) {
        var obj: [String: Any] = ["ok": true]
        for (k, v) in extra { obj[k] = v }
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{\"ok\":true}".utf8)
        return (200, data)
    }

    private static func errorBody(_ message: String) -> Data {
        let payload: [String: Any] = ["ok": false, "error": message]
        return (try? JSONSerialization.data(withJSONObject: payload))
            ?? Data("{\"ok\":false,\"error\":\"\(message)\"}".utf8)
    }

    // MARK: - HTTP parsing

    struct HTTPRequest {
        let method: String
        let path: String
        let body: Data
    }

    private static func parseRequest(_ data: Data) -> HTTPRequest? {
        // Find end of headers (\r\n\r\n)
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }

        let headerData = data[..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])

        // Parse Content-Length
        var contentLength = 0
        for line in lines.dropFirst() {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                contentLength = Int(value) ?? 0
            }
        }

        let bodyStart = headerEnd.upperBound
        let available = data.count - bodyStart
        if available < contentLength {
            return nil // need more data
        }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        return HTTPRequest(method: method, path: path, body: body)
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "OK"
        }
    }
}

// MARK: - Errors

public enum DebugServerError: Error, CustomStringConvertible {
    case invalidPort(UInt16)

    public var description: String {
        switch self {
        case .invalidPort(let p): return "Invalid port: \(p)"
        }
    }
}

// MARK: - Snapshot DTOs

struct DebugRoom: Encodable {
    let id: String
    let displayName: String
    let unreadCount: UInt64
    let isEncrypted: Bool
    let isPublic: Bool
    let isInvited: Bool
    let topic: String?

    init(_ r: RoomInfo) {
        self.id = r.id
        self.displayName = r.displayName
        self.unreadCount = r.unreadCount
        self.isEncrypted = r.isEncrypted
        self.isPublic = r.isPublic
        self.isInvited = r.isInvited
        self.topic = r.topic
    }
}

struct DebugReaction: Encodable {
    let eventId: String
    let key: String
    let sender: String

    init(_ r: ReactionInfo) {
        self.eventId = r.eventId
        self.key = r.key
        self.sender = r.sender
    }
}

struct DebugMessage: Encodable {
    let eventId: String
    let sender: String
    let body: String
    let messageType: String
    let timestampMs: UInt64
    let isEdited: Bool
    let repliedToEventId: String?
    let reactions: [DebugReaction]
    let mediaMimeType: String?
    let mediaSize: UInt64?

    init(_ m: MessageInfo) {
        self.eventId = m.eventId
        self.sender = m.sender
        self.body = m.body
        self.messageType = m.messageType
        self.timestampMs = m.timestampMs
        self.isEdited = m.isEdited
        self.repliedToEventId = m.repliedToEventId
        self.reactions = m.reactions.map(DebugReaction.init)
        self.mediaMimeType = m.mediaMimeType
        self.mediaSize = m.mediaSize
    }
}

struct DebugSnapshot: Encodable {
    let profile: String
    let isLoggedIn: Bool
    let isLoading: Bool
    let isCheckingSession: Bool
    let isSyncActive: Bool
    let loggedInUserId: String?
    let homeserverURL: String
    let errorMessage: String?
    let selectedRoomId: String?
    let rooms: [DebugRoom]
    let messages: [DebugMessage]
    let hasMoreMessages: Bool
    let isLoadingMoreMessages: Bool
    let typingUsers: [String: [String]]
    let currentRoomTypingUsers: [String]

    @MainActor
    static func from(appState: AppState) -> DebugSnapshot {
        DebugSnapshot(
            profile: appState.profile,
            isLoggedIn: appState.isLoggedIn,
            isLoading: appState.isLoading,
            isCheckingSession: appState.isCheckingSession,
            isSyncActive: appState.isSyncActive,
            loggedInUserId: appState.loggedInUserId,
            homeserverURL: appState.homeserverURL,
            errorMessage: appState.errorMessage,
            selectedRoomId: appState.selectedRoomId,
            rooms: appState.rooms.map(DebugRoom.init),
            messages: appState.messages.map(DebugMessage.init),
            hasMoreMessages: appState.hasMoreMessages,
            isLoadingMoreMessages: appState.isLoadingMoreMessages,
            typingUsers: appState.typingUsers,
            currentRoomTypingUsers: appState.currentRoomTypingUsers
        )
    }
}

// MARK: - Shared encoder

extension JSONEncoder {
    static let debug: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

// MARK: - DebugClient (test helper)

/// Thin HTTP client for driving `DebugServer` from Swift Testing, which can't
/// `import Foundation` in the command-line toolchain (the `_Testing_Foundation`
/// shim module has no swiftmodule there). Living inside ParlotteLib gives tests
/// a Foundation-free surface.
public struct DebugClient: Sendable {
    public let baseURL: URL

    public init(port: UInt16) {
        self.baseURL = URL(string: "http://127.0.0.1:\(port)")!
    }

    public func get(_ path: String) async throws -> (status: Int, body: [String: Any]) {
        let (data, response) = try await URLSession.shared.data(from: url(path))
        return (Self.statusCode(response), Self.decodeJSON(data))
    }

    public func post(_ path: String, body: [String: Any]) async throws -> (status: Int, body: [String: Any]) {
        let payload = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: Self.request(url(path), method: "POST", body: payload))
        return (Self.statusCode(response), Self.decodeJSON(data))
    }

    /// Post a raw string body. Used to test malformed-JSON handling.
    public func postText(_ path: String, text: String) async throws -> Int {
        let (_, response) = try await URLSession.shared.data(for: Self.request(url(path), method: "POST", body: Data(text.utf8)))
        return Self.statusCode(response)
    }

    private func url(_ path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    private static func request(_ url: URL, method: String, body: Data?) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        return req
    }

    private static func statusCode(_ response: URLResponse) -> Int {
        (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    private static func decodeJSON(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

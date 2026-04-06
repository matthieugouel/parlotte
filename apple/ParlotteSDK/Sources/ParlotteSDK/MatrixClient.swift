import Foundation
@_exported import ParlotteFFI

/// Thread-safe async wrapper around the blocking UniFFI ParlotteClientFfi.
/// All blocking Rust calls are dispatched off the main thread via Task.detached.
public actor MatrixClient {
    private let ffi: ParlotteClientFfi

    public init(homeserverURL: String, storePath: String?) throws {
        self.ffi = try ParlotteClientFfi(homeserverUrl: homeserverURL, storePath: storePath)
    }

    public func login(username: String, password: String) async throws -> SessionInfo {
        let ffi = self.ffi
        return try await Task.detached {
            try ffi.login(username: username, password: password)
        }.value
    }

    public func session() -> MatrixSessionData? {
        ffi.session()
    }

    public func restoreSession(_ sessionData: MatrixSessionData) async throws {
        let ffi = self.ffi
        try await Task.detached {
            try ffi.restoreSession(sessionData: sessionData)
        }.value
    }

    public func logout() async throws {
        let ffi = self.ffi
        try await Task.detached {
            try ffi.logout()
        }.value
    }

    public func rooms() async throws -> [RoomInfo] {
        let ffi = self.ffi
        return try await Task.detached {
            try ffi.rooms()
        }.value
    }

    public func syncOnce() async throws {
        let ffi = self.ffi
        try await Task.detached {
            try ffi.syncOnce()
        }.value
    }

    public func createRoom(name: String, isPublic: Bool = false) async throws -> String {
        let ffi = self.ffi
        return try await Task.detached {
            try ffi.createRoom(name: name, isPublic: isPublic)
        }.value
    }

    public func publicRooms() async throws -> [PublicRoomInfo] {
        let ffi = self.ffi
        return try await Task.detached {
            try ffi.publicRooms()
        }.value
    }

    public func joinRoom(roomId: String) async throws {
        let ffi = self.ffi
        try await Task.detached {
            try ffi.joinRoom(roomId: roomId)
        }.value
    }

    public func leaveRoom(roomId: String) async throws {
        let ffi = self.ffi
        try await Task.detached {
            try ffi.leaveRoom(roomId: roomId)
        }.value
    }

    public func roomMembers(roomId: String) async throws -> [RoomMemberInfo] {
        let ffi = self.ffi
        return try await Task.detached {
            try ffi.roomMembers(roomId: roomId)
        }.value
    }

    public func inviteUser(roomId: String, userId: String) async throws {
        let ffi = self.ffi
        try await Task.detached {
            try ffi.inviteUser(roomId: roomId, userId: userId)
        }.value
    }

    public func sendMessage(roomId: String, body: String) async throws {
        let ffi = self.ffi
        try await Task.detached {
            try ffi.sendMessage(roomId: roomId, body: body)
        }.value
    }

    public func messages(roomId: String, limit: UInt64 = 50) async throws -> [MessageInfo] {
        let ffi = self.ffi
        return try await Task.detached {
            try ffi.messages(roomId: roomId, limit: limit)
        }.value
    }

    public nonisolated var isSyncing: Bool {
        ffi.isSyncing()
    }
}

import ParlotteLib
import ParlotteSDK
import SwiftUI

struct RoomListView: View {
    @Environment(AppState.self) private var appState
    @State private var showCreateRoom = false
    @State private var showExploreRooms = false
    @State private var showProfile = false

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            // User header (tap to open profile)
            Button {
                showProfile = true
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let userId = appState.loggedInUserId {
                            Text(appState.displayName ?? localpart(from: userId))
                                .font(.title3)
                                .fontWeight(.semibold)

                            Text(serverName(from: userId))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Circle()
                        .fill(appState.isSyncActive ? .green : .orange)
                        .frame(width: 8, height: 8)
                        .help(appState.isSyncActive ? "Connected" : "Disconnected")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()
                .opacity(0.3)

            List(selection: $appState.selectedRoomId) {
                ForEach(appState.rooms, id: \.id) { room in
                    HStack(spacing: 10) {
                        Image(systemName: room.isPublic ? "globe" : "lock.fill")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        Text(room.displayName)
                            .font(.title3)
                            .lineLimit(1)

                        if room.isInvited {
                            Text("Invite")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.2))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }

                        Spacer()

                        if room.unreadCount > 0 {
                            Text("\(room.unreadCount)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue)
                                .clipShape(Capsule())
                        }

                        if room.isEncrypted {
                            Image(systemName: "shield.lefthalf.filled")
                                .font(.callout)
                                .foregroundStyle(.green)
                                .help("Encrypted")
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(room.id)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
                .opacity(0.3)

            HStack(spacing: 16) {
                Button {
                    showCreateRoom = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Create Room")

                Button {
                    showExploreRooms = true
                } label: {
                    Image(systemName: "globe")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Explore Public Rooms")

                Button {
                    Task { await appState.refreshRooms() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    Task { await appState.logout() }
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Logout")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
                .environment(appState)
        }
        .sheet(isPresented: $showCreateRoom) {
            CreateRoomView()
                .environment(appState)
        }
        .sheet(isPresented: $showExploreRooms) {
            ExploreRoomsView()
                .environment(appState)
        }
    }

    private func localpart(from userId: String) -> String {
        // "@alice:server" -> "alice"
        if userId.hasPrefix("@"), let colon = userId.firstIndex(of: ":") {
            return String(userId[userId.index(after: userId.startIndex)..<colon])
        }
        return userId
    }

    private func serverName(from userId: String) -> String {
        // "@alice:server" -> "server"
        if let colon = userId.firstIndex(of: ":") {
            return String(userId[userId.index(after: colon)...])
        }
        return ""
    }
}

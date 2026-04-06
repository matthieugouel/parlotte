import SwiftUI
import ParlotteSDK

struct RoomListView: View {
    @Environment(AppState.self) private var appState
    @State private var showCreateRoom = false
    @State private var showExploreRooms = false

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            List(selection: $appState.selectedRoomId) {
                ForEach(appState.rooms, id: \.id) { room in
                    HStack(spacing: 8) {
                        Image(systemName: room.isPublic ? "globe" : "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)

                        Text(room.displayName)
                            .lineLimit(1)

                        if room.isInvited {
                            Text("Invite")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.2))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }

                        Spacer()

                        if room.isEncrypted {
                            Image(systemName: "shield.lefthalf.filled")
                                .font(.caption2)
                                .foregroundStyle(.green)
                                .help("Encrypted")
                        }
                    }
                    .tag(room.id)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
                .opacity(0.3)

            HStack(spacing: 12) {
                Button {
                    showCreateRoom = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Create Room")

                Button {
                    showExploreRooms = true
                } label: {
                    Image(systemName: "globe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Explore Public Rooms")

                Button {
                    Task { await appState.refreshRooms() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    Task { await appState.logout() }
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Logout")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
}

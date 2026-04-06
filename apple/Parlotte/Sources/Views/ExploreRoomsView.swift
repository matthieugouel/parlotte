import SwiftUI
import ParlotteSDK

struct ExploreRoomsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var publicRooms: [PublicRoomInfo] = []
    @State private var isLoading = true
    @State private var joinedRoomIds: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Explore Public Rooms")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding()

            Divider()

            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if publicRooms.isEmpty {
                Spacer()
                Text("No public rooms found")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(publicRooms, id: \.id) { room in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(room.name ?? room.id)
                                .fontWeight(.medium)

                            if let topic = room.topic, !topic.isEmpty {
                                Text(topic)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            HStack(spacing: 8) {
                                Label("\(room.memberCount)", systemImage: "person.2")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)

                                if let alias = room.alias {
                                    Text(alias)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }

                        Spacer()

                        if joinedRoomIds.contains(room.id) {
                            Text("Joined")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Join") {
                                Task {
                                    await appState.joinRoom(roomId: room.id)
                                    joinedRoomIds.insert(room.id)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .task {
            joinedRoomIds = Set(appState.rooms.map(\.id))
            publicRooms = await appState.fetchPublicRooms()
            isLoading = false
        }
    }
}

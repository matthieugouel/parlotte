import ParlotteLib
import ParlotteSDK
import SwiftUI

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
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding(Spacing.lg)

            Divider()
                .opacity(0.5)

            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if publicRooms.isEmpty {
                Spacer()
                Text("No public rooms found")
                    .foregroundStyle(AppColor.textTertiary)
                Spacer()
            } else {
                List(publicRooms, id: \.id) { room in
                    HStack(spacing: Spacing.md) {
                        RoomAvatar(
                            roomName: room.name ?? "?",
                            roomId: room.id,
                            isPublic: true,
                            size: 32
                        )

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(room.name ?? room.id)
                                .font(.roomName)

                            if let topic = room.topic, !topic.isEmpty {
                                Text(topic)
                                    .font(.roomPreview)
                                    .foregroundStyle(AppColor.textTertiary)
                                    .lineLimit(2)
                            }

                            HStack(spacing: Spacing.sm) {
                                Label("\(room.memberCount)", systemImage: "person.2")
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppColor.textTertiary)

                                if let alias = room.alias {
                                    Text(alias)
                                        .font(.system(size: 10))
                                        .foregroundStyle(AppColor.textTertiary)
                                }
                            }
                        }

                        Spacer()

                        if joinedRoomIds.contains(room.id) {
                            Text("Joined")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppColor.textTertiary)
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
                    .padding(.vertical, Spacing.xs)
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 420, minHeight: 300)
        .task {
            joinedRoomIds = Set(appState.rooms.map(\.id))
            publicRooms = await appState.fetchPublicRooms()
            isLoading = false
        }
    }
}

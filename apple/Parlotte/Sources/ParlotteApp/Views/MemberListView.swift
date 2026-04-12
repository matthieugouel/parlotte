import ParlotteLib
import ParlotteSDK
import SwiftUI

struct MemberListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var members: [RoomMemberInfo] = []
    @State private var isLoading = true

    let roomId: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Members")
                    .font(.title2)
                    .fontWeight(.semibold)

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
            } else if members.isEmpty {
                Spacer()
                Text("No members found")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(members, id: \.userId) { member in
                    HStack(spacing: 12) {
                        Image(systemName: iconName(for: member.role))
                            .font(.body)
                            .foregroundStyle(iconColor(for: member.role))
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName ?? member.userId)
                                .font(.body)

                            if member.displayName != nil {
                                Text(member.userId)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        Text(member.role.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(roleBadgeColor(for: member.role))
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 350, minHeight: 300)
        .task {
            members = await appState.fetchRoomMembers(roomId: roomId)
            isLoading = false
        }
    }

    private func iconName(for role: String) -> String {
        switch role {
        case "admin": return "crown.fill"
        case "moderator": return "shield.fill"
        default: return "person.fill"
        }
    }

    private func iconColor(for role: String) -> Color {
        switch role {
        case "admin": return .orange
        case "moderator": return .blue
        default: return .secondary
        }
    }

    private func roleBadgeColor(for role: String) -> Color {
        switch role {
        case "admin": return .orange.opacity(0.2)
        case "moderator": return .blue.opacity(0.2)
        default: return .secondary.opacity(0.15)
        }
    }
}

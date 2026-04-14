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
            } else if members.isEmpty {
                Spacer()
                Text("No members found")
                    .foregroundStyle(AppColor.textTertiary)
                Spacer()
            } else {
                List(members, id: \.userId) { member in
                    HStack(spacing: Spacing.md) {
                        MemberAvatar(userId: member.userId, size: 32)

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(member.displayName ?? localpart(from: member.userId))
                                .font(.senderName)

                            if member.displayName != nil {
                                Text(member.userId)
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppColor.textTertiary)
                            }
                        }

                        Spacer()

                        Text(member.role.capitalized)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xxs)
                            .background(roleBadgeColor(for: member.role))
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, Spacing.xxs)
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

    private func localpart(from userId: String) -> String {
        if userId.hasPrefix("@"), let colon = userId.firstIndex(of: ":") {
            return String(userId[userId.index(after: userId.startIndex)..<colon])
        }
        return userId
    }

    private func roleBadgeColor(for role: String) -> Color {
        switch role {
        case "admin": return .orange.opacity(0.15)
        case "moderator": return AppColor.accent.opacity(0.15)
        default: return AppColor.surfaceHover
        }
    }
}

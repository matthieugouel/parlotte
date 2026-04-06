import SwiftUI
import ParlotteSDK

struct RoomDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var messageText = ""
    @State private var showInvite = false
    @State private var inviteUserId = ""

    private var selectedRoom: some View {
        let room = appState.rooms.first { $0.id == appState.selectedRoomId }
        return Group {
            if let room {
                VStack {
                    HStack(spacing: 6) {
                        Text(room.displayName)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Image(systemName: room.isPublic ? "globe" : "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(room.isPublic ? "Public room" : "Private room")

                        if room.isEncrypted {
                            Image(systemName: "shield.lefthalf.filled")
                                .font(.caption)
                                .foregroundStyle(.green)
                                .help("End-to-end encrypted")
                        }

                        Spacer()

                        Button {
                            showInvite = true
                        } label: {
                            Image(systemName: "person.badge.plus")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Invite User")
                    }

                    if let topic = room.topic, !topic.isEmpty {
                        HStack {
                            Text(topic)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private var currentRoom: RoomInfo? {
        appState.rooms.first { $0.id == appState.selectedRoomId }
    }

    var body: some View {
        if let room = currentRoom, room.isInvited {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "envelope.badge")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("You've been invited to")
                    .foregroundStyle(.secondary)
                Text(room.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)
                HStack(spacing: 12) {
                    Button("Accept") {
                        Task { await appState.joinRoom(roomId: room.id) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            roomContent
        }
    }

    private var roomContent: some View {
        VStack(spacing: 0) {
            // Room header
            selectedRoom
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)

            Divider()

            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(appState.messages, id: \.eventId) { message in
                            MessageBubble(message: message)
                                .id(message.eventId)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .onChange(of: appState.messages.count) { _, _ in
                    if let last = appState.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.eventId, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Compose area
            HStack(spacing: 8) {
                TextField("Send a message...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .onSubmit {
                        send()
                    }

                Button {
                    send()
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .alert("Invite User", isPresented: $showInvite) {
            TextField("@user:server", text: $inviteUserId)
            Button("Invite") {
                let userId = inviteUserId
                inviteUserId = ""
                Task { await appState.inviteUser(userId: userId) }
            }
            Button("Cancel", role: .cancel) {
                inviteUserId = ""
            }
        }
    }

    private func send() {
        let body = messageText
        messageText = ""
        Task { await appState.sendMessage(body: body) }
    }
}

struct MessageBubble: View {
    let message: MessageInfo

    private var senderName: String {
        // Extract localpart from @user:server
        let userId = message.sender
        if userId.hasPrefix("@"), let colonIndex = userId.firstIndex(of: ":") {
            return String(userId[userId.index(after: userId.startIndex)..<colonIndex])
        }
        return userId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(senderName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Text(formattedTime)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(message.body)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }

    private var formattedTime: String {
        let date = Date(timeIntervalSince1970: Double(message.timestampMs) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

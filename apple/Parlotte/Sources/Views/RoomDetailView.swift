import SwiftUI
import ParlotteSDK

struct RoomDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var messageText = ""
    @State private var showInvite = false
    @State private var inviteUserId = ""
    @State private var showLeaveConfirm = false
    @State private var showMembers = false

    private var selectedRoom: some View {
        let room = appState.rooms.first { $0.id == appState.selectedRoomId }
        return Group {
            if let room {
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Text(room.displayName)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Image(systemName: room.isPublic ? "globe" : "lock.fill")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .help(room.isPublic ? "Public room" : "Private room")

                        if room.isEncrypted {
                            Image(systemName: "shield.lefthalf.filled")
                                .font(.callout)
                                .foregroundStyle(.green)
                                .help("End-to-end encrypted")
                        }

                        Spacer()

                        Button {
                            showMembers = true
                        } label: {
                            Image(systemName: "person.2")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .help("Members")

                        Button {
                            showInvite = true
                        } label: {
                            Image(systemName: "person.badge.plus")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .help("Invite User")

                        Button {
                            showLeaveConfirm = true
                        } label: {
                            Image(systemName: "arrow.right.square")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Leave Room")
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
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("You've been invited to")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(room.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)
                HStack(spacing: 12) {
                    Button("Accept") {
                        Task { await appState.joinRoom(roomId: room.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
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
                .padding(.top, 10)
                .padding(.bottom, 10)

            Divider()

            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(appState.messages, id: \.eventId) { message in
                            MessageBubble(
                                message: message,
                                isOwnMessage: message.sender == appState.loggedInUserId,
                                onEdit: { newBody in
                                    Task { await appState.editMessage(eventId: message.eventId, newBody: newBody) }
                                },
                                onDelete: {
                                    Task { await appState.deleteMessage(eventId: message.eventId) }
                                }
                            )
                            .id(message.eventId)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
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
            HStack(spacing: 10) {
                TextField("Send a message...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(1...5)
                    .onSubmit {
                        send()
                    }

                Button {
                    send()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.body)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
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
        .sheet(isPresented: $showMembers) {
            if let roomId = appState.selectedRoomId {
                MemberListView(roomId: roomId)
                    .environment(appState)
            }
        }
        .alert("Leave Room", isPresented: $showLeaveConfirm) {
            Button("Leave", role: .destructive) {
                if let roomId = appState.selectedRoomId {
                    Task { await appState.leaveRoom(roomId: roomId) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to leave this room?")
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
    let isOwnMessage: Bool
    let onEdit: (String) -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editText = ""
    @State private var isHovered = false
    @State private var showDeleteConfirm = false

    private var senderName: String {
        let userId = message.sender
        if userId.hasPrefix("@"), let colonIndex = userId.firstIndex(of: ":") {
            return String(userId[userId.index(after: userId.startIndex)..<colonIndex])
        }
        return userId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(senderName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Text(formattedTime)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if message.isEdited {
                    Text("(edited)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if isOwnMessage && isHovered && !isEditing {
                    HStack(spacing: 6) {
                        Button {
                            editText = message.body
                            isEditing = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Edit")

                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Delete")
                    }
                    .transition(.opacity)
                }
            }

            if isEditing {
                HStack(spacing: 8) {
                    TextField("Edit message...", text: $editText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .lineLimit(1...5)
                        .onSubmit {
                            let text = editText
                            isEditing = false
                            onEdit(text)
                        }

                    Button("Save") {
                        let text = editText
                        isEditing = false
                        onEdit(text)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Cancel") {
                        isEditing = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                messageContent
                    .font(.title3)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.04) : .clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .alert("Delete Message", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this message?")
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        switch message.messageType {
        case "image":
            Label(message.body, systemImage: "photo")
                .foregroundStyle(.secondary)
        case "file":
            Label(message.body, systemImage: "doc")
                .foregroundStyle(.secondary)
        case "video":
            Label(message.body, systemImage: "film")
                .foregroundStyle(.secondary)
        case "audio":
            Label(message.body, systemImage: "waveform")
                .foregroundStyle(.secondary)
        case "location":
            Label(message.body, systemImage: "location")
                .foregroundStyle(.secondary)
        case "emote":
            if let attributed = formattedAttributedString {
                Text("* \(senderName) ") + Text(attributed)
            } else {
                Text("* \(senderName) \(message.body)")
                    .italic()
            }
        default:
            if let attributed = formattedAttributedString {
                Text(attributed)
            } else {
                Text(message.body)
            }
        }
    }

    private var formattedAttributedString: AttributedString? {
        guard let html = message.formattedBody else { return nil }
        // Wrap in a basic HTML document so NSAttributedString parses it correctly
        let wrapped = "<html><body style=\"font-family: -apple-system; font-size: 16px;\">\(html)</body></html>"
        guard let data = wrapped.data(using: .utf8),
              let nsAttr = try? NSAttributedString(
                  data: data,
                  options: [.documentType: NSAttributedString.DocumentType.html,
                            .characterEncoding: String.Encoding.utf8.rawValue],
                  documentAttributes: nil
              ) else { return nil }
        return try? AttributedString(nsAttr, including: \.swiftUI)
    }

    private var formattedTime: String {
        let date = Date(timeIntervalSince1970: Double(message.timestampMs) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

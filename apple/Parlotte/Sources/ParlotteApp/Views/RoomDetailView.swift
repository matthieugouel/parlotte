import ParlotteLib
import ParlotteSDK
import SwiftUI

struct RoomDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var messageText = ""
    @State private var showInvite = false
    @State private var inviteUserId = ""
    @State private var showLeaveConfirm = false
    @State private var showMembers = false
    @State private var replyingTo: MessageInfo?

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
            messageList

            // Typing indicator
            if !appState.currentRoomTypingUsers.isEmpty {
                TypingIndicator(userIds: appState.currentRoomTypingUsers)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
            }

            Divider()

            // Compose area
            VStack(spacing: 0) {
                if let reply = replyingTo {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.blue)
                            .frame(width: 3, height: 28)

                        VStack(alignment: .leading, spacing: 0) {
                            Text(reply.sender)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                            Text(reply.body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            replyingTo = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(.bar)

                    Divider()
                }

                HStack(spacing: 10) {
                    TextField("Send a message...", text: $messageText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .lineLimit(1...5)
                        .onSubmit {
                            send()
                        }
                        .onChange(of: messageText) { oldValue, newValue in
                            let wasEmpty = oldValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            let isEmpty = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            if wasEmpty && !isEmpty {
                                Task { await appState.sendTypingNotice(isTyping: true) }
                            } else if !wasEmpty && isEmpty {
                                Task { await appState.sendTypingNotice(isTyping: false) }
                            }
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
        .onChange(of: appState.selectedRoomId) {
            replyingTo = nil
        }
    }

    private var messageList: some View {
        MessageScrollView(
            itemCount: appState.messages.count,
            lastItemId: appState.messages.last?.eventId,
            isLoadingOlder: appState.isLoadingMoreMessages,
            onScrollToTop: {
                if appState.hasMoreMessages && !appState.isLoadingMoreMessages {
                    Task { await appState.loadMoreMessages() }
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 6) {
                if appState.hasMoreMessages {
                    HStack {
                        Spacer()
                        if appState.isLoadingMoreMessages {
                            ProgressView("Loading older messages...")
                                .controlSize(.small)
                        } else {
                            Button("Load older messages") {
                                Task { await appState.loadMoreMessages() }
                            }
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                ForEach(Array(appState.messages.enumerated()), id: \.element.eventId) { index, message in
                    if index == 0 {
                        DateSeparator(timestamp: message.timestampMs)
                    } else {
                        let prevDate = Self.calendarDay(appState.messages[index - 1].timestampMs)
                        let thisDate = Self.calendarDay(message.timestampMs)
                        if prevDate != thisDate {
                            DateSeparator(timestamp: message.timestampMs)
                        }
                    }

                    MessageBubble(
                        message: message,
                        isOwnMessage: message.sender == appState.loggedInUserId,
                        repliedMessage: message.repliedToEventId.flatMap { replyId in
                            appState.messages.first { $0.eventId == replyId }
                        },
                        onReply: {
                            replyingTo = message
                        },
                        onEdit: { newBody in
                            Task { await appState.editMessage(eventId: message.eventId, newBody: newBody) }
                        },
                        onDelete: {
                            Task { await appState.deleteMessage(eventId: message.eventId) }
                        }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    private func send() {
        let body = messageText
        let reply = replyingTo
        messageText = ""
        replyingTo = nil
        Task {
            if let reply {
                await appState.sendReply(eventId: reply.eventId, body: body)
            } else {
                await appState.sendMessage(body: body)
            }
        }
    }
}

private struct TypingIndicator: View {
    let userIds: [String]

    private var displayText: String {
        let names = userIds.map { userId -> String in
            if userId.hasPrefix("@"), let colon = userId.firstIndex(of: ":") {
                return String(userId[userId.index(after: userId.startIndex)..<colon])
            }
            return userId
        }
        switch names.count {
        case 1: return "\(names[0]) is typing..."
        case 2: return "\(names[0]) and \(names[1]) are typing..."
        default: return "Several people are typing..."
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

struct MessageBubble: View {
    let message: MessageInfo
    let isOwnMessage: Bool
    let repliedMessage: MessageInfo?
    let onReply: () -> Void
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

                if isHovered && !isEditing {
                    HStack(spacing: 6) {
                        Button {
                            onReply()
                        } label: {
                            Image(systemName: "arrowshape.turn.up.left")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Reply")

                        if isOwnMessage {
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
                    }
                    .transition(.opacity)
                }
            }

            if let replied = repliedMessage {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.blue.opacity(0.6))
                        .frame(width: 3, height: 28)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(replied.sender)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                        Text(replied.body)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 2)
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

// MARK: - Date Separator

private struct DateSeparator: View {
    let timestamp: UInt64

    var body: some View {
        HStack {
            VStack { Divider() }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .layoutPriority(1)
            VStack { Divider() }
        }
        .padding(.vertical, 6)
    }

    private var label: String {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}

// MARK: - Helpers

extension RoomDetailView {
    static func calendarDay(_ timestampMs: UInt64) -> DateComponents {
        let date = Date(timeIntervalSince1970: Double(timestampMs) / 1000.0)
        return Calendar.current.dateComponents([.year, .month, .day], from: date)
    }
}

import AppKit
import ParlotteLib
import ParlotteSDK
import SwiftUI
import UniformTypeIdentifiers

struct RoomDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var messageText = ""
    @State private var showInvite = false
    @State private var inviteUserId = ""
    @State private var showLeaveConfirm = false
    @State private var showMembers = false
    @State private var showSettings = false
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
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .help("Room Settings")

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
                    Button {
                        attachFile()
                    } label: {
                        Image(systemName: "paperclip")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Attach file")

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
        .sheet(isPresented: $showSettings) {
            if let roomId = appState.selectedRoomId {
                RoomSettingsView(roomId: roomId)
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
                        },
                        onReact: { key in
                            Task { await appState.toggleReaction(eventId: message.eventId, key: key) }
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

    private func attachFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .pdf, .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await appState.sendAttachment(fileURL: url) }
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
    @Environment(AppState.self) private var appState
    let message: MessageInfo
    let isOwnMessage: Bool
    let repliedMessage: MessageInfo?
    let onReply: () -> Void
    let onEdit: (String) -> Void
    let onDelete: () -> Void
    let onReact: (String) -> Void

    @State private var isEditing = false
    @State private var editText = ""
    @State private var isHovered = false
    @State private var showDeleteConfirm = false
    @State private var showReactionPicker = false

    private var senderName: String {
        let userId = message.sender
        if userId.hasPrefix("@"), let colonIndex = userId.firstIndex(of: ":") {
            return String(userId[userId.index(after: userId.startIndex)..<colonIndex])
        }
        return userId
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Avatar
            MemberAvatar(userId: message.sender, size: 32)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(appState.memberDisplayName(for: message.sender) ?? senderName)
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

                    if (isHovered || showReactionPicker) && !isEditing {
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

                            Button {
                                showReactionPicker = true
                            } label: {
                                Image(systemName: "face.smiling")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("React")
                            .popover(isPresented: $showReactionPicker) {
                                ReactionPicker { key in
                                    showReactionPicker = false
                                    onReact(key)
                                }
                            }

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

            if !message.reactions.isEmpty {
                ReactionBar(
                    reactions: message.reactions,
                    currentUserId: appState.loggedInUserId ?? "",
                    onToggle: onReact
                )
            }
            } // end inner VStack
        } // end HStack
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
            MediaImageView(message: message)
        case "file":
            MediaFileView(message: message)
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

// MARK: - Reactions

private struct ReactionBar: View {
    let reactions: [ReactionInfo]
    let currentUserId: String
    let onToggle: (String) -> Void

    private var grouped: [(key: String, count: Int, userReacted: Bool)] {
        var dict: [String: (count: Int, userReacted: Bool)] = [:]
        for r in reactions {
            var entry = dict[r.key, default: (count: 0, userReacted: false)]
            entry.count += 1
            if r.sender == currentUserId { entry.userReacted = true }
            dict[r.key] = entry
        }
        return dict.map { (key: $0.key, count: $0.value.count, userReacted: $0.value.userReacted) }
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(grouped, id: \.key) { group in
                Button {
                    onToggle(group.key)
                } label: {
                    HStack(spacing: 2) {
                        Text(group.key)
                            .font(.caption)
                        if group.count > 1 {
                            Text("\(group.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(group.userReacted
                                  ? Color.accentColor.opacity(0.2)
                                  : Color.secondary.opacity(0.1))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(group.userReacted ? Color.accentColor : .clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ReactionPicker: View {
    let onPick: (String) -> Void

    private let commonEmoji = [
        "\u{1f44d}", "\u{1f44e}", "\u{2764}\u{fe0f}", "\u{1f602}",
        "\u{1f60d}", "\u{1f914}", "\u{1f389}", "\u{1f44f}",
        "\u{1f525}", "\u{1f440}", "\u{2705}", "\u{274c}",
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 4), spacing: 4) {
            ForEach(commonEmoji, id: \.self) { emoji in
                Button {
                    onPick(emoji)
                } label: {
                    Text(emoji)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
    }
}

// MARK: - Helpers

extension RoomDetailView {
    static func calendarDay(_ timestampMs: UInt64) -> DateComponents {
        let date = Date(timeIntervalSince1970: Double(timestampMs) / 1000.0)
        return Calendar.current.dateComponents([.year, .month, .day], from: date)
    }
}

// MARK: - Member Avatar

private struct MemberAvatar: View {
    @Environment(AppState.self) private var appState
    let userId: String
    let size: CGFloat

    @State private var avatarImage: NSImage?

    private var initial: String {
        let name = appState.memberDisplayName(for: userId) ?? localpart(from: userId)
        return String(name.prefix(1)).uppercased()
    }

    var body: some View {
        Group {
            if let image = avatarImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle()
                        .fill(avatarColor)
                    Text(initial)
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: appState.avatarUrl(for: userId)) {
            guard let mxcUrl = appState.avatarUrl(for: userId) else {
                avatarImage = nil
                return
            }
            if let data = await appState.loadMedia(mxcUri: mxcUrl) {
                avatarImage = NSImage(data: data)
            }
        }
    }

    private var avatarColor: Color {
        // Deterministic color from userId hash
        let hash = abs(userId.hashValue)
        let colors: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .mint, .cyan]
        return colors[hash % colors.count]
    }

    private func localpart(from userId: String) -> String {
        if userId.hasPrefix("@"), let colon = userId.firstIndex(of: ":") {
            return String(userId[userId.index(after: userId.startIndex)..<colon])
        }
        return userId
    }
}

// MARK: - Media

private struct MediaImageView: View {
    @Environment(AppState.self) private var appState
    let message: MessageInfo

    @State private var imageData: Data?
    @State private var loadFailed = false
    @State private var showFullSize = false

    private var aspectRatio: CGFloat {
        guard let w = message.mediaWidth, let h = message.mediaHeight,
              w > 0, h > 0 else { return 4.0 / 3.0 }
        return CGFloat(w) / CGFloat(h)
    }

    private var maxWidth: CGFloat { 300 }

    @State private var decodedImage: NSImage?

    var body: some View {
        Group {
            if let nsImage = decodedImage {
                Button {
                    showFullSize = true
                } label: {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: maxWidth)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showFullSize) {
                    FullSizeImageView(image: nsImage, filename: message.body) {
                        showFullSize = false
                    }
                }
            } else if loadFailed {
                Label("Failed to load image", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                    ProgressView()
                }
                .frame(width: maxWidth, height: maxWidth / aspectRatio)
            }
        }
        .task(id: message.eventId) {
            // Optimistic path: bytes we just uploaded are held locally.
            let bytes: Data?
            if let pending = appState.pendingAttachments[message.eventId] {
                bytes = pending
            } else if let mxc = message.mediaSource {
                bytes = await appState.loadMedia(mxcUri: mxc)
            } else {
                bytes = nil
            }

            if let bytes, let img = NSImage(data: bytes) {
                decodedImage = img
            } else {
                loadFailed = true
            }
        }
    }
}

private struct FullSizeImageView: View {
    let image: NSImage
    let filename: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(filename)
                    .font(.headline)
                Spacer()
                Button("Done") { onClose() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

private struct MediaFileView: View {
    @Environment(AppState.self) private var appState
    let message: MessageInfo

    @State private var isDownloading = false
    @State private var errorText: String?

    private var sizeLabel: String {
        guard let size = message.mediaSize else { return "" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(message.body)
                    .font(.body)
                if !sizeLabel.isEmpty {
                    Text(sizeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            if isDownloading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    saveFile()
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .help("Download")
                .disabled(message.mediaSource == nil)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func saveFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = message.body
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        isDownloading = true
        errorText = nil
        Task {
            defer { isDownloading = false }
            // Pending (just-uploaded) bytes are stored locally.
            if let pending = appState.pendingAttachments[message.eventId] {
                do {
                    try pending.write(to: destination)
                } catch {
                    errorText = error.localizedDescription
                }
                return
            }
            guard let mxc = message.mediaSource else {
                errorText = "No media source"
                return
            }
            guard let data = await appState.loadMedia(mxcUri: mxc) else {
                errorText = "Download failed"
                return
            }
            do {
                try data.write(to: destination)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}

import ParlotteLib
import ParlotteSDK
import SwiftUI

struct RoomSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let roomId: String

    @State private var name: String = ""
    @State private var topic: String = ""
    @State private var didInit = false

    private var room: RoomInfo? {
        appState.rooms.first { $0.id == roomId }
    }

    private var hasChanges: Bool {
        guard let room else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentTopic = room.topic ?? ""
        return (trimmedName != room.displayName && !trimmedName.isEmpty)
            || trimmedTopic != currentTopic
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Room Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Room name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Topic")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Room topic", text: $topic, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!hasChanges || appState.isUpdatingRoomSettings)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            guard !didInit, let room else { return }
            name = room.displayName
            topic = room.topic ?? ""
            didInit = true
        }
    }

    private func save() {
        guard let room else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentTopic = room.topic ?? ""
        let nameChanged = trimmedName != room.displayName && !trimmedName.isEmpty
        let topicChanged = trimmedTopic != currentTopic

        Task {
            if nameChanged {
                await appState.updateRoomName(roomId: roomId, name: trimmedName)
            }
            if topicChanged {
                await appState.updateRoomTopic(roomId: roomId, topic: trimmedTopic)
            }
            dismiss()
        }
    }
}

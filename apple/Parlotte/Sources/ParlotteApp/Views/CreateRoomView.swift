import ParlotteLib
import SwiftUI

struct CreateRoomView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var roomName = ""
    @State private var isPublic = false
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Create Room")
                .font(.headline)

            TextField("Room name", text: $roomName)
                .textFieldStyle(.roundedBorder)

            Toggle("Public room", isOn: $isPublic)

            if isPublic {
                Text("Anyone can find and join this room.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Only invited users can join.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    isCreating = true
                    let name = roomName
                    let pub_ = isPublic
                    Task {
                        await appState.createRoom(name: name, isPublic: pub_)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

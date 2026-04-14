import ParlotteLib
import SwiftUI

struct CreateRoomView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var roomName = ""
    @State private var isPublic = false
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Text("Create Room")
                .font(.system(size: 16, weight: .semibold))

            TextField("Room name", text: $roomName)
                .textFieldStyle(.roundedBorder)
                .font(.messageBody)

            Toggle("Public room", isOn: $isPublic)

            Text(isPublic ? "Anyone can find and join this room." : "Only invited users can join.")
                .font(.system(size: 12))
                .foregroundStyle(AppColor.textTertiary)

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
        .padding(Spacing.xl)
        .frame(width: 320)
    }
}

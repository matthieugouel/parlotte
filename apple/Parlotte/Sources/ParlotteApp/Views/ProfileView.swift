import AppKit
import ParlotteLib
import ParlotteSDK
import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var editingName = ""
    @State private var isEditingName = false
    @State private var avatarData: Data?

    var body: some View {
        VStack(spacing: 20) {
            Text("Profile")
                .font(.title2)
                .fontWeight(.semibold)

            // Avatar
            VStack(spacing: 8) {
                avatarView
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())

                HStack(spacing: 12) {
                    Button("Change") {
                        pickAvatar()
                    }

                    if appState.avatarUrl != nil {
                        Button("Remove", role: .destructive) {
                            Task { await appState.removeAvatar() }
                        }
                    }
                }
                .font(.caption)
            }

            Divider()

            // Display name
            VStack(alignment: .leading, spacing: 6) {
                Text("Display Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isEditingName {
                    HStack {
                        TextField("Display name", text: $editingName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { saveDisplayName() }

                        Button("Save") { saveDisplayName() }
                            .disabled(editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Cancel") { isEditingName = false }
                    }
                } else {
                    HStack {
                        Text(appState.displayName ?? localpart(from: appState.loggedInUserId ?? ""))
                            .font(.body)

                        Spacer()

                        Button {
                            editingName = appState.displayName ?? ""
                            isEditingName = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // User ID (read-only)
            VStack(alignment: .leading, spacing: 6) {
                Text("User ID")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(appState.loggedInUserId ?? "")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if appState.isUpdatingProfile {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 360, height: 400)
        .task {
            if let url = appState.avatarUrl {
                avatarData = await appState.loadMedia(mxcUri: url)
            }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let data = avatarData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            // Initials fallback
            let name = appState.displayName ?? localpart(from: appState.loggedInUserId ?? "?")
            let initial = String(name.prefix(1)).uppercased()
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.3))
                Text(initial)
                    .font(.title)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }
        }
    }

    private func saveDisplayName() {
        let name = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isEditingName = false
        Task { await appState.updateDisplayName(name) }
    }

    private func pickAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an avatar image"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let data = try? Data(contentsOf: url) else { return }
        let mimeType = detectMimeType(for: url)

        // Show preview immediately
        avatarData = data

        Task {
            await appState.updateAvatar(data: data, mimeType: mimeType)
        }
    }

    private func detectMimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        return "image/png"
    }

    private func localpart(from userId: String) -> String {
        if userId.hasPrefix("@"), let colon = userId.firstIndex(of: ":") {
            return String(userId[userId.index(after: userId.startIndex)..<colon])
        }
        return userId
    }
}

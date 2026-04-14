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
        VStack(spacing: Spacing.xl) {
            Text("Profile")
                .font(.system(size: 18, weight: .semibold))

            // Avatar
            VStack(spacing: Spacing.sm) {
                avatarView
                    .frame(width: AvatarSize.profile, height: AvatarSize.profile)
                    .clipShape(Circle())

                HStack(spacing: Spacing.md) {
                    Button("Change") {
                        pickAvatar()
                    }

                    if appState.avatarUrl != nil {
                        Button("Remove", role: .destructive) {
                            Task { await appState.removeAvatar() }
                        }
                    }
                }
                .font(.system(size: 12, weight: .medium))
            }

            Divider()
                .opacity(0.5)

            // Display name
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Display Name")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.textTertiary)
                    .textCase(.uppercase)

                if isEditingName {
                    HStack {
                        TextField("Display name", text: $editingName)
                            .textFieldStyle(.roundedBorder)
                            .font(.messageBody)
                            .onSubmit { saveDisplayName() }

                        Button("Save") { saveDisplayName() }
                            .disabled(editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Cancel") { isEditingName = false }
                    }
                } else {
                    HStack {
                        Text(appState.displayName ?? localpart(from: appState.loggedInUserId ?? ""))
                            .font(.messageBody)

                        Spacer()

                        Button {
                            editingName = appState.displayName ?? ""
                            isEditingName = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // User ID (read-only)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("User ID")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.textTertiary)
                    .textCase(.uppercase)

                Text(appState.loggedInUserId ?? "")
                    .font(.messageBody)
                    .foregroundStyle(AppColor.textSecondary)
                    .textSelection(.enabled)
            }

            Divider()
                .opacity(0.5)

            // Appearance
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Appearance")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.textTertiary)
                    .textCase(.uppercase)

                Picker("", selection: Binding(
                    get: { appState.appearance },
                    set: { appState.appearance = $0 }
                )) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayLabel).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if appState.isUpdatingProfile {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(Spacing.xxl)
        .frame(width: 360, height: 520)
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
            let name = appState.displayName ?? localpart(from: appState.loggedInUserId ?? "?")
            let initial = String(name.prefix(1)).uppercased()
            ZStack {
                Circle()
                    .fill(AppColor.accent.opacity(0.2))
                Text(initial)
                    .font(.system(size: AvatarSize.profile * 0.4, weight: .semibold))
                    .foregroundStyle(AppColor.accent)
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

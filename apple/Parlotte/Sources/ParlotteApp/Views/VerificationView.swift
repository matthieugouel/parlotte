import ParlotteLib
import ParlotteSDK
import SwiftUI

struct VerificationSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Spacing.lg) {
            header

            if let state = appState.verificationStateValue {
                content(for: state)
            } else if let request = appState.activeVerification {
                incomingOrOutgoing(request: request)
            } else {
                ProgressView()
            }

            if let error = appState.verificationErrorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actions
        }
        .padding(Spacing.xxl)
        .frame(width: 420)
    }

    @ViewBuilder
    private var header: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.blue)
            Text("Device Verification")
                .font(.system(size: 16, weight: .semibold))
            if let info = appState.activeVerification {
                Text(info.weStarted
                     ? "Confirm this is you on your other device."
                     : "Another device is asking to verify.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private func content(for state: VerificationState) -> some View {
        switch state {
        case .pending:
            pendingView(waitingForRemoteAccept: appState.activeVerification?.weStarted ?? false)
        case .ready:
            VStack(spacing: Spacing.sm) {
                Text("Ready to start")
                    .font(.system(size: 13, weight: .medium))
                Text("Both devices are ready. Start the emoji comparison below.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
        case .sasStarted:
            VStack(spacing: Spacing.sm) {
                ProgressView()
                Text("Exchanging keys…")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.textSecondary)
            }
        case .sasReadyToCompare(let emojis):
            emojiGrid(emojis)
        case .sasConfirmed:
            VStack(spacing: Spacing.sm) {
                ProgressView()
                Text("Waiting for the other device to confirm…")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.textSecondary)
            }
        case .done:
            VStack(spacing: Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
                Text("Verified")
                    .font(.system(size: 14, weight: .semibold))
                Text("This device is now verified.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.textSecondary)
            }
        case .cancelled(let reason):
            VStack(spacing: Spacing.sm) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.red)
                Text("Cancelled")
                    .font(.system(size: 14, weight: .semibold))
                Text(reason)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private func pendingView(waitingForRemoteAccept: Bool) -> some View {
        VStack(spacing: Spacing.sm) {
            ProgressView()
            Text(waitingForRemoteAccept
                 ? "Waiting for the other device to accept…"
                 : "A verification request has arrived.")
                .font(.system(size: 12))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private func incomingOrOutgoing(request: VerificationRequestInfo) -> some View {
        pendingView(waitingForRemoteAccept: request.weStarted)
    }

    @ViewBuilder
    private func emojiGrid(_ emojis: [VerificationEmoji]) -> some View {
        VStack(spacing: Spacing.sm) {
            Text("Compare the emojis with your other device.")
                .font(.system(size: 12))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 4), spacing: Spacing.md) {
                ForEach(Array(emojis.enumerated()), id: \.offset) { _, emoji in
                    VStack(spacing: 4) {
                        Text(emoji.symbol)
                            .font(.system(size: 34))
                        Text(emoji.description)
                            .font(.system(size: 10))
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                }
            }
            .padding(.horizontal, Spacing.sm)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: Spacing.md) {
            switch appState.verificationStateValue {
            case .pending:
                if appState.activeVerification?.weStarted == false {
                    Button("Accept") {
                        Task { await appState.acceptVerification() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(appState.isProcessingVerification)
                }
                Button("Cancel", role: .cancel) {
                    Task {
                        await appState.cancelVerification()
                        await appState.dismissVerification()
                        dismiss()
                    }
                }
            case .ready:
                Button("Start Emoji Compare") {
                    Task { await appState.startSasVerification() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(appState.isProcessingVerification)
                Button("Cancel", role: .cancel) {
                    Task {
                        await appState.cancelVerification()
                        await appState.dismissVerification()
                        dismiss()
                    }
                }
            case .sasReadyToCompare:
                Button("They Match") {
                    Task { await appState.confirmSasVerification() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(appState.isProcessingVerification)
                Button("Don't Match", role: .destructive) {
                    Task { await appState.sasMismatch() }
                }
                .disabled(appState.isProcessingVerification)
            case .done, .cancelled:
                Button("Close") {
                    Task {
                        await appState.dismissVerification()
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            case .sasStarted, .sasConfirmed, .none:
                Button("Cancel", role: .cancel) {
                    Task {
                        await appState.cancelVerification()
                        await appState.dismissVerification()
                        dismiss()
                    }
                }
            }

            if appState.isProcessingVerification {
                ProgressView().controlSize(.small)
            }
        }
    }
}

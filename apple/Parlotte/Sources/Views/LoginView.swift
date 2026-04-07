import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var detectTask: Task<Void, Never>?
    /// Tracks the last URL we successfully detected, to avoid re-detecting on focus changes.
    @State private var lastDetectedURL: String = ""

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 24) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Parlotte")
                .font(.largeTitle)
                .fontWeight(.bold)

            VStack(spacing: 12) {
                TextField("Homeserver URL", text: $appState.homeserverURL)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: appState.homeserverURL) {
                        scheduleDetection()
                    }
                    .onSubmit {
                        // Detect immediately on Enter
                        detectTask?.cancel()
                        let url = appState.homeserverURL
                        detectTask = Task {
                            lastDetectedURL = url
                            await appState.detectLoginMethods()
                        }
                    }

                if appState.isDetectingLoginMethods {
                    ProgressView()
                        .controlSize(.small)
                }

                // Password login fields
                if appState.supportsPassword {
                    TextField("Username", text: $appState.username)
                        .textFieldStyle(.roundedBorder)

                    SecureField("Password", text: $appState.password)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            Task { await appState.login() }
                        }

                    Button {
                        Task { await appState.login() }
                    } label: {
                        if appState.isLoading && !appState.supportsSso {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Login with Password")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(appState.isLoading || appState.username.isEmpty || appState.password.isEmpty)
                }

                // SSO login buttons
                if appState.supportsSso {
                    if appState.supportsPassword {
                        Divider()
                            .padding(.vertical, 4)
                    }

                    if appState.ssoProviders.isEmpty {
                        Button {
                            Task { await appState.loginWithSso() }
                        } label: {
                            if appState.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Login with SSO", systemImage: "globe")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(appState.isLoading)
                    } else {
                        ForEach(appState.ssoProviders, id: \.id) { provider in
                            Button {
                                Task { await appState.loginWithSso(idpId: provider.id) }
                            } label: {
                                if appState.isLoading {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Login with \(provider.name)", systemImage: "globe")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(appState.isLoading)
                        }
                    }
                }
            }
            .frame(maxWidth: 300)

            if let error = appState.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .frame(maxWidth: 300)
            }
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 400)
    }

    private func scheduleDetection() {
        detectTask?.cancel()

        let url = appState.homeserverURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only detect if it looks like a valid URL and has changed
        guard url.hasPrefix("http://") || url.hasPrefix("https://"),
              url != lastDetectedURL else { return }

        detectTask = Task {
            // Debounce: wait 800ms after the user stops typing
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            lastDetectedURL = url
            await appState.detectLoginMethods()
        }
    }
}

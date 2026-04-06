import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState

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

                TextField("Username", text: $appState.username)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $appState.password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await appState.login() }
                    }
            }
            .frame(maxWidth: 300)

            if let error = appState.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .frame(maxWidth: 300)
            }

            Button {
                Task { await appState.login() }
            } label: {
                if appState.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Login")
                        .frame(maxWidth: 300)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(appState.isLoading || appState.username.isEmpty || appState.password.isEmpty)
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 400)
    }
}

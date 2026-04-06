import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    private static let loginSize    = NSSize(width: 360, height: 560)
    private static let loginMinSize = NSSize(width: 360, height: 560)
    private static let mainSize     = NSSize(width: 1100, height: 750)
    private static let mainMinSize  = NSSize(width: 700, height: 450)

    var body: some View {
        Group {
            if appState.isCheckingSession {
                Color.clear
            } else if appState.isLoggedIn {
                MainView()
            } else {
                LoginView()
            }
        }
        .task {
            await appState.restoreSession()
        }
        .onChange(of: appState.isCheckingSession) { _, checking in
            guard !checking else { return }
            applyWindowSize(loggedIn: appState.isLoggedIn)
        }
        .onChange(of: appState.isLoggedIn) { _, loggedIn in
            guard !appState.isCheckingSession else { return }
            applyWindowSize(loggedIn: loggedIn)
        }
    }

    private func applyWindowSize(loggedIn: Bool) {
        if loggedIn {
            resizeWindow(to: Self.mainSize, minSize: Self.mainMinSize)
        } else {
            resizeWindow(to: Self.loginSize, minSize: Self.loginMinSize)
        }
    }

    private func resizeWindow(to size: NSSize, minSize: NSSize) {
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else { return }
        window.minSize = minSize
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let oldFrame = window.frame
        let newOrigin = NSPoint(
            x: oldFrame.midX - size.width / 2,
            y: oldFrame.midY - size.height / 2
        )
        let newFrame = NSRect(origin: newOrigin, size: size)
        window.setFrame(newFrame, display: true, animate: true)
    }
}

struct MainView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            RoomListView()
                .padding(.top, 28)
                .frame(width: 250)
                .background(.black.opacity(0.15))

            Divider()
                .opacity(0.3)

            if appState.selectedRoomId != nil {
                RoomDetailView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No Room Selected")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    Text("Select a room from the sidebar to start chatting.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
    }
}

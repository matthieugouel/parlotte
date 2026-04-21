import AppKit
import AuthenticationServices
import Foundation

/// Drives a single OIDC authorization-code flow via `ASWebAuthenticationSession`.
/// The authorization URL is opened in a system-managed browser sheet; when the
/// provider redirects to the custom scheme, the session returns the full
/// callback URL for the core to finish the token exchange.
@MainActor
public final class OidcAuthSession: NSObject {
    public static let callbackScheme = "io.github.nxthdr.parlotte"
    public static let callbackURL = "\(callbackScheme):/oauth-callback"

    public override init() {
        super.init()
    }

    public func authenticate(authorizationURL: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: Self.callbackScheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: OidcAuthError.noCallback)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                continuation.resume(throwing: OidcAuthError.cannotStart)
            }
        }
    }
}

extension OidcAuthSession: ASWebAuthenticationPresentationContextProviding {
    public nonisolated func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        }
    }
}

public enum OidcAuthError: Error {
    case cannotStart
    case noCallback
}

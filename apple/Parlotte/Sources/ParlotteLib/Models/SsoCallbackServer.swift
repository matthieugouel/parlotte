import Foundation
import Network

/// A minimal local HTTP server that listens for a single SSO callback request.
/// The SSO provider redirects the browser to `http://localhost:<port>?loginToken=...`
/// and this server captures that URL, returns a success page, then shuts down.
///
/// The listener binds to the loopback interface only, and the caller supplies a
/// random `state` parameter which must appear verbatim in the callback query —
/// any attacker-controlled request missing or mismatching `state` is rejected.
actor SsoCallbackServer {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?
    private let expectedState: String

    /// `expectedState` is verified against the `state` query parameter on the
    /// callback. Use a cryptographically random value (see `AppState`).
    init(expectedState: String) {
        self.expectedState = expectedState
    }

    /// Start listening on a random available loopback port. Returns the port.
    func start() throws -> UInt16 {
        // Pin the listener to the loopback interface so nothing on the LAN /
        // VPN / Tailscale can race the browser to our callback port.
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        let listener = try NWListener(using: params, on: .any)
        self.listener = listener

        let port: UInt16 = try {
            let semaphore = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var assignedPort: UInt16 = 0
            nonisolated(unsafe) var listenerError: Error?

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    assignedPort = listener.port?.rawValue ?? 0
                    semaphore.signal()
                case .failed(let error):
                    listenerError = error
                    semaphore.signal()
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                Task { await self?.handleConnection(connection) }
            }

            listener.start(queue: DispatchQueue(label: "sso-callback-server"))
            semaphore.wait()

            if let error = listenerError {
                throw error
            }
            return assignedPort
        }()

        return port
    }

    /// Wait for the SSO callback. Returns the full callback URL string.
    func waitForCallback() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue(label: "sso-connection"))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self else { return }

            if let error {
                Task { await self.failWith(error) }
                return
            }

            guard let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            // Parse the HTTP request line to extract the path + query
            // Format: "GET /?loginToken=xyz HTTP/1.1\r\n..."
            guard let firstLine = request.split(separator: "\r\n").first else {
                connection.cancel()
                return
            }

            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2 else {
                connection.cancel()
                return
            }

            let path = String(parts[1])
            let callbackUrl = "http://localhost\(path)"

            // Reject any callback that doesn't carry the state we issued.
            // Without this, a local process that guesses (or scans) the port
            // could POST its own `loginToken` and trick us into signing into
            // the attacker's account.
            guard Self.hasMatchingState(in: callbackUrl, expected: self.expectedState) else {
                let body = "invalid state"
                let deny = "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
                connection.send(content: deny.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                // Keep listening — the legitimate browser redirect may still
                // arrive after a curious scanner pokes the port.
                return
            }

            // Send a success response to the browser
            let html = """
            <html><body style="font-family: -apple-system, sans-serif; text-align: center; padding-top: 100px;">
            <h1>Login successful!</h1>
            <p>You can close this tab and return to Parlotte.</p>
            </body></html>
            """
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\nContent-Length: \(html.utf8.count)\r\n\r\n\(html)"

            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })

            Task { await self.completeWith(callbackUrl) }
        }
    }

    private func completeWith(_ url: String) {
        listener?.cancel()
        listener = nil
        continuation?.resume(returning: url)
        continuation = nil
    }

    private func failWith(_ error: Error) {
        listener?.cancel()
        listener = nil
        continuation?.resume(throwing: error)
        continuation = nil
    }

    /// Constant-time check that the callback URL's `state` query parameter
    /// matches the value we issued. The comparison is done on the parsed
    /// query items, so the order of parameters in the URL doesn't matter.
    private static func hasMatchingState(in callbackUrl: String, expected: String) -> Bool {
        guard let components = URLComponents(string: callbackUrl),
              let items = components.queryItems else { return false }
        guard let actual = items.first(where: { $0.name == "state" })?.value else {
            return false
        }
        // Constant-time comparison to avoid timing side channels against a
        // secret, even though the window is short.
        let a = Array(actual.utf8)
        let e = Array(expected.utf8)
        guard a.count == e.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ e[i] }
        return diff == 0
    }
}

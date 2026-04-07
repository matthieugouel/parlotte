import Foundation
import Network

/// A minimal local HTTP server that listens for a single SSO callback request.
/// The SSO provider redirects the browser to `http://localhost:<port>?loginToken=...`
/// and this server captures that URL, returns a success page, then shuts down.
actor SsoCallbackServer {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?

    /// Start listening on a random available port. Returns the port number.
    func start() throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener

        let port: UInt16 = try {
            let semaphore = DispatchSemaphore(value: 0)
            var assignedPort: UInt16 = 0
            var listenerError: Error?

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
}

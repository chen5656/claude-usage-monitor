import Foundation

/// Minimal local HTTP server using POSIX sockets to capture an OAuth callback.
/// Avoids Network.framework (NWListener) which throws EINVAL on some macOS versions.
final class CallbackServer: @unchecked Sendable {
    private var serverFd: Int32 = -1
    private(set) var port: UInt16 = 0

    /// Synchronous — bind/listen are instant.
    func start() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError("socket") }

        // Allow quick reuse of the port after restart
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        // Bind to loopback on any available port
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = 0                            // 0 → OS picks a free port
        addr.sin_addr   = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)  // 127.0.0.1

        let bindOK = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Foundation.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        } == 0
        guard bindOK           else { close(fd); throw posixError("bind") }
        guard listen(fd, 1) == 0 else { close(fd); throw posixError("listen") }

        // Discover the OS-assigned port
        var bound = sockaddr_in()
        var len   = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }

        serverFd = fd
        port     = UInt16(bigEndian: bound.sin_port)
        return port
    }

    /// Suspends the async task while accept() blocks a GCD thread (no cooperative-pool starvation).
    func waitForCallback() async throws -> (code: String, state: String) {
        guard serverFd >= 0 else { throw OAuthError.callbackFailed }
        let fd = serverFd                      // capture before any cancel race

        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let client = accept(fd, nil, nil)
                guard client >= 0 else {
                    // Socket was closed (cancel) or other error
                    cont.resume(throwing: OAuthError.cancelled)
                    return
                }
                defer { close(client) }

                // Read HTTP request
                var buf = [UInt8](repeating: 0, count: 8192)
                let n = recv(client, &buf, buf.count - 1, 0)
                guard n > 0 else {
                    cont.resume(throwing: OAuthError.callbackFailed)
                    return
                }

                let req = String(bytes: buf.prefix(Int(n)), encoding: .utf8) ?? ""
                guard let result = Self.parseCallback(from: req) else {
                    Self.send(client, "HTTP/1.1 400 Bad Request\r\n\r\n")
                    cont.resume(throwing: OAuthError.callbackFailed)
                    return
                }

                Self.send(client, """
                    HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n\
                    <!DOCTYPE html><html><head><title>Done</title>\
                    <style>body{font-family:system-ui;text-align:center;padding-top:80px;background:#f5f5f7}</style>\
                    </head><body><h2>&#x2705; Login successful!</h2>\
                    <p>You can close this tab and return to AI Usage Tracker for Claude Subscription.</p></body></html>
                    """)
                cont.resume(returning: result)
            }
        }
    }

    /// Close the socket — unblocks any pending accept() call.
    func cancel() {
        let fd = serverFd
        serverFd = -1
        if fd >= 0 { close(fd) }
    }

    // MARK: - Helpers

    private static func parseCallback(from request: String) -> (code: String, state: String)? {
        let firstLine = request.split(separator: "\r\n").first
                     ?? request.split(separator: "\n").first
        guard let firstLine else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2,
              let comps = URLComponents(string: "http://localhost" + String(parts[1])),
              let code  = comps.queryItems?.first(where: { $0.name == "code"  })?.value,
              let state = comps.queryItems?.first(where: { $0.name == "state" })?.value
        else { return nil }
        return (code: code, state: state)
    }

    private static func send(_ fd: Int32, _ s: String) {
        s.withCString { ptr in _ = Foundation.send(fd, ptr, strlen(ptr), 0) }
    }

    private func posixError(_ op: String) -> Error {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "\(op): \(String(cString: strerror(errno)))"])
    }
}

import AppKit
import CryptoKit
import Foundation

/// Handles the OAuth 2.0 + PKCE browser login flow used by Claude Code.
final class OAuthManager: @unchecked Sendable {
    static let shared = OAuthManager()

    // These constants were extracted from the Claude Code CLI binary.
    private let clientID     = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let authorizeURL = "https://claude.ai/oauth/authorize"
    private let tokenURL     = "https://platform.claude.com/v1/oauth/token"
    private let scopes       = ["user:profile", "user:inference", "user:sessions:claude_code"]

    private var callbackServer: CallbackServer?

    private init() {}

    // MARK: - Public

    func login() async throws -> OAuthTokens {
        let verifier   = generateCodeVerifier()
        let challenge  = generateCodeChallenge(from: verifier)
        let state      = UUID().uuidString.replacingOccurrences(of: "-", with: "")

        let server = CallbackServer()
        callbackServer = server
        let port = try server.start()          // sync bind/listen – instant

        let redirectURI = "http://localhost:\(port)/callback"
        let authURL     = buildAuthorizeURL(redirectURI: redirectURI,
                                            challenge: challenge,
                                            state: state)

        let opened = await MainActor.run { NSWorkspace.shared.open(authURL) }
        guard opened else {
            throw OAuthError.browserOpenFailed
        }

        let (code, returnedState) = try await server.waitForCallback()
        callbackServer = nil

        guard returnedState == state else { throw OAuthError.stateMismatch }

        // Pass state back to the token endpoint — Anthropic requires it
        return try await exchangeCode(code: code, verifier: verifier,
                                      redirectURI: redirectURI, state: state)
    }

    func refresh(_ tokens: OAuthTokens) async throws -> OAuthTokens {
        guard let rt = tokens.refreshToken else { throw OAuthError.noToken }
        let body: [String: String] = [
            "grant_type":    "refresh_token",
            "refresh_token": rt,
            "client_id":     clientID,
            "scope":         scopes.joined(separator: " ")
        ]
        return try await postToken(body)
    }

    func cancelLogin() {
        callbackServer?.cancel()
        callbackServer = nil
    }

    // MARK: - Private

    private func buildAuthorizeURL(redirectURI: String, challenge: String, state: String) -> URL {
        var c = URLComponents(string: authorizeURL)!
        c.queryItems = [
            URLQueryItem(name: "code",                  value: "true"),
            URLQueryItem(name: "client_id",             value: clientID),
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "redirect_uri",          value: redirectURI),
            URLQueryItem(name: "scope",                 value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge",        value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state",                 value: state),
        ]
        return c.url!
    }

    private func exchangeCode(code: String, verifier: String,
                              redirectURI: String, state: String) async throws -> OAuthTokens {
        let body: [String: String] = [
            "grant_type":    "authorization_code",
            "code":          code,
            "redirect_uri":  redirectURI,
            "client_id":     clientID,
            "code_verifier": verifier,
            "state":         state          // required by Anthropic's token endpoint
        ]
        return try await postToken(body)
    }

    private func postToken(_ body: [String: String]) async throws -> OAuthTokens {
        var req = URLRequest(url: URL(string: tokenURL)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OAuthError.tokenExchangeFailed(msg)
        }

        struct TR: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Int? }
        let tr = try JSONDecoder().decode(TR.self, from: data)
        return OAuthTokens(
            accessToken:  tr.access_token,
            refreshToken: tr.refresh_token,
            expiresAt:    Date().addingTimeInterval(TimeInterval(tr.expires_in ?? 3600))
        )
    }

    // MARK: - PKCE helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

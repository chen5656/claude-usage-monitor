import SwiftUI

struct LoginView: View {
    @State private var isLoggingIn  = false
    @State private var errorMessage: String?

    let onSuccess: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "cpu")
                .font(.system(size: 44))
                .foregroundColor(.accentColor)

            Text("Claude Usage Monitor")
                .font(.title2).fontWeight(.semibold)

            Text("Log in with your Claude.ai account to monitor your plan usage limits.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if let msg = errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            Button(action: startLogin) {
                HStack(spacing: 8) {
                    if isLoggingIn { ProgressView().controlSize(.small) }
                    Text(isLoggingIn ? "Waiting for browser…" : "Log in with Claude.ai")
                }
                .frame(width: 230)
            }
            .disabled(isLoggingIn)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if isLoggingIn {
                Button("Cancel") { cancel() }
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(36)
        .frame(width: 420, height: 320)
    }

    private func startLogin() {
        isLoggingIn  = true
        errorMessage = nil
        Task {
            do {
                let tokens = try await OAuthManager.shared.login()
                if KeychainManager.shared.saveTokens(tokens) {
                    await MainActor.run { onSuccess() }
                } else {
                    await MainActor.run {
                        errorMessage = "Failed to save session to Keychain."
                        isLoggingIn  = false
                    }
                }
            } catch OAuthError.cancelled {
                await MainActor.run { isLoggingIn = false }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoggingIn  = false
                }
            }
        }
    }

    private func cancel() {
        OAuthManager.shared.cancelLogin()
        isLoggingIn = false
    }
}

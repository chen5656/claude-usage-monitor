import SwiftUI

struct LoginView: View {
    @State private var isLoggingIn  = false
    @State private var errorMessage: String?

    let onSuccess: () -> Void
    let onDemo: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "cpu")
                        .font(.system(size: 36))
                        .foregroundColor(.accentColor)
                        .padding(10)
                        .background(
                            Circle()
                                .fill(Color.accentColor.opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Usage Tracker for Claude")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))

                        Text("Track plan limits from your menu bar")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                Text("Log in with your Claude.ai account to view your latest usage and reset windows.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let msg = errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.orange.opacity(0.12))
                    )
                }

                Button(action: startLogin) {
                    HStack(spacing: 8) {
                        if isLoggingIn { ProgressView().controlSize(.small) }
                        Text(isLoggingIn ? "Waiting for browser…" : "Log in with Claude.ai")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isLoggingIn)
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)

                Button(action: startDemo) {
                    Text("Try Demo Mode")
                        .frame(maxWidth: .infinity)
                }
                .disabled(isLoggingIn)
                .buttonStyle(.bordered)
                .controlSize(.large)

                if isLoggingIn {
                    Button("Cancel") { cancel() }
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .padding(28)
        }
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

    private func startDemo() {
        errorMessage = nil
        onDemo()
    }
}

import SwiftUI

struct LoginView: View {
    @State private var apiKey        = ""
    @State private var isValidating  = false
    @State private var errorMessage: String?

    let onSuccess: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cpu")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            Text("Claude Usage Monitor")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Enter your Anthropic API key to monitor your usage.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            SecureField("sk-ant-api03-…", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)

            if let msg = errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            Button(isValidating ? "Validating…" : "Connect") {
                Task { await validate() }
            }
            .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || isValidating)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)

            Link("Get your API key →",
                 destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                .font(.caption)
        }
        .padding(32)
        .frame(width: 420, height: 300)
    }

    @MainActor
    private func validate() async {
        isValidating = true
        errorMessage = nil
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let valid = try await AnthropicService().validateAPIKey(key)
            if valid {
                if KeychainManager.shared.saveAPIKey(key) {
                    onSuccess()
                } else {
                    errorMessage = "Failed to save API key to Keychain."
                    isValidating = false
                }
            } else {
                errorMessage = "Invalid API key. Please try again."
                isValidating = false
            }
        } catch {
            errorMessage = error.localizedDescription
            isValidating = false
        }
    }
}

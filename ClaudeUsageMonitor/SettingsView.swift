import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var controller: StatusBarController
    @State private var selectedInterval = 600
    @State private var showChangeKey    = false

    private let intervals: [(label: String, seconds: Int)] = [
        ("30 Seconds",        30),
        ("1 Minute",          60),
        ("5 Minutes",        300),
        ("10 Minutes",       600)
    ]

    var body: some View {
        Form {
            Section("Refresh Interval") {
                Picker("Interval", selection: $selectedInterval) {
                    ForEach(intervals, id: \.seconds) { item in
                        Text(item.label).tag(item.seconds)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: selectedInterval) { value in
                    controller.setRefreshInterval(TimeInterval(value))
                }
            }

            Section("Account") {
                Button("Change API Key…") { showChangeKey = true }
                Button("Log Out", role: .destructive) { controller.logout() }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 340, height: 280)
        .onAppear {
            selectedInterval = Int(controller.refreshInterval)
        }
        .sheet(isPresented: $showChangeKey) {
            ChangeAPIKeyView {
                showChangeKey = false
                Task { await controller.refreshUsage() }
            }
        }
    }
}

struct ChangeAPIKeyView: View {
    @State private var apiKey       = ""
    @State private var isValidating = false
    @State private var errorMessage: String?

    let onSuccess: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Change API Key")
                .font(.headline)

            SecureField("New API key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)

            if let msg = errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack(spacing: 12) {
                Button("Cancel") { onSuccess() }
                    .keyboardShortcut(.escape)

                Button(isValidating ? "Saving…" : "Save") {
                    Task { await save() }
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || isValidating)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
        }
        .padding(28)
        .frame(width: 340, height: 200)
    }

    @MainActor
    private func save() async {
        isValidating = true
        errorMessage = nil
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let valid = try await AnthropicService().validateAPIKey(key)
            if valid {
                _ = KeychainManager.shared.saveAPIKey(key)
                onSuccess()
            } else {
                errorMessage = "Invalid API key."
                isValidating = false
            }
        } catch {
            errorMessage = error.localizedDescription
            isValidating = false
        }
    }
}

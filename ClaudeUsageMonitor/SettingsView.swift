import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var controller: StatusBarController
    @State private var selectedInterval = 600

    private let intervals: [(label: String, seconds: Int)] = [
        ("30 Seconds",  30),
        ("1 Minute",    60),
        ("5 Minutes",  300),
        ("10 Minutes", 600)
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
                Button("Log Out", role: .destructive) {
                    controller.logout()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 300, height: 240)
        .onAppear {
            selectedInterval = Int(controller.refreshInterval)
        }
    }
}

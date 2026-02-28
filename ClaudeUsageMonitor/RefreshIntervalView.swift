import SwiftUI

struct RefreshIntervalView: View {
    @Binding var selectedInterval: TimeInterval

    private let options: [(label: String, value: TimeInterval)] = [
        ("30s", 30),
        ("1m",  60),
        ("5m",  300),
        ("10m", 600),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Refresh Interval")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)

            Picker("", selection: $selectedInterval) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .padding(.top, 6)
        .frame(width: 240)
    }
}

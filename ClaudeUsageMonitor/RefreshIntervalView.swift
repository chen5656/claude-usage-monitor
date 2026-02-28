import AppKit
import SwiftUI

struct RefreshIntervalView: View {
    @Binding var selectedInterval: TimeInterval
    let onRefresh: () -> Void

    private let options: [(label: String, value: TimeInterval)] = [
        ("30s", 30),
        ("1m",  60),
        ("5m",  300),
        ("10m", 600),
    ]

    var body: some View {
        MenuCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Refresh", systemImage: "arrow.clockwise")

                VStack(alignment: .center, spacing: 12) {
                    Button(action: onRefresh) {
                        Label("Refresh Now", systemImage: "arrow.clockwise.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Refresh interval")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        Picker("", selection: $selectedInterval) {
                            ForEach(options, id: \.value) { option in
                                Text(option.label).tag(option.value)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(width: 320)
    }
}

struct ShortcutCopyView: View {
    @StateObject private var store = ShortcutStore()
    @State private var draftShortcuts: [ShortcutItem] = []
    @State private var copied = false
    @State private var isEditing = false

    var body: some View {
        MenuCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    SectionHeader(title: "Quick Copy", systemImage: "doc.on.clipboard")

                    Spacer(minLength: 12)

                    if copied {
                        Label("Copied", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green)
                            .transition(.opacity.combined(with: .scale))
                    }

                    Button(isEditing ? "Cancel" : "Edit") {
                        if isEditing {
                            isEditing = false
                        } else {
                            draftShortcuts = store.shortcuts
                            isEditing = true
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .semibold))
                }

                if isEditing {
                    Text("Update labels and commands stored in your config file.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach($draftShortcuts) { $shortcut in
                                VStack(alignment: .leading, spacing: 4) {
                                    TextField("Label", text: $shortcut.label)
                                        .textFieldStyle(.roundedBorder)

                                    TextField("Command", text: $shortcut.command)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11, design: .monospaced))
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 160)

                    HStack {
                        Button("Reset") {
                            draftShortcuts = ShortcutStore.defaultShortcuts
                        }
                        .buttonStyle(.borderless)

                        Spacer()

                        Button("Save") { commitEdits() }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSaveDisabled)
                    }
                } else {
                    Text("Paste directly in your terminal to switch models or modes.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                    ], spacing: 8) {
                        ForEach(store.shortcuts) { option in
                            Button(action: { copyShortcut(option) }) {
                                Text(option.label)
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.primary)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.02))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
        .frame(width: 320)
    }

    private var isSaveDisabled: Bool {
        draftShortcuts.contains {
            $0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            $0.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func commitEdits() {
        let cleaned = draftShortcuts.map { item in
            ShortcutItem(
                id: item.id,
                label: item.label.trimmingCharacters(in: .whitespacesAndNewlines),
                command: item.command.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        store.update(cleaned)
        isEditing = false
    }

    private func copyShortcut(_ shortcut: ShortcutItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(shortcut.command, forType: .string)

        withAnimation(.easeOut(duration: 0.2)) {
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.2)) {
                copied = false
            }
        }
    }
}

private struct MenuCard<Content: View>: View {
    let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

private struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(.primary)
    }
}

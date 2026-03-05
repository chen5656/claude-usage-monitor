import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RefreshIntervalView: View {
    @Binding var selectedInterval: TimeInterval
    let onRefresh: () -> Void

    private let options: [(label: String, value: TimeInterval)] = [
        ("1m",  60),
        ("5m",  300),
        ("10m", 600),
        ("30m", 1800),
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
    @State private var editingIndex = 0
    @FocusState private var focusedField: EditingField?

    private enum EditingField: Hashable {
        case label
        case command
    }

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
                            focusedField = nil
                        } else {
                            draftShortcuts = store.shortcuts
                            editingIndex = 0
                            isEditing = true
                            focusedField = .label
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .semibold))
                }

                if isEditing {
                    Text("Update labels and commands.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    if draftShortcuts.isEmpty {
                        Text("No shortcuts to edit.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 10)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 6) {
                                TextField("Label", text: $draftShortcuts[editingIndex].label)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedField, equals: .label)

                                TextField("Command", text: $draftShortcuts[editingIndex].command)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                                    .focused($focusedField, equals: .command)
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.02))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                            .onPasteCommand(of: [.plainText]) { _ in
                                pasteIntoFocusedField()
                            }
                            
                            HStack(spacing: 8) {
                                HStack(spacing: 6) {
                                    Button {
                                        if editingIndex > 0 {
                                            editingIndex -= 1
                                        }
                                    } label: {
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 11, weight: .semibold))
                                            .frame(width: 24, height: 24)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(editingIndex == 0)

                                    Button {
                                        if editingIndex < draftShortcuts.count - 1 {
                                            editingIndex += 1
                                        }
                                    } label: {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .semibold))
                                            .frame(width: 24, height: 24)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(editingIndex >= draftShortcuts.count - 1)

                                    Text("\(editingIndex + 1)/\(draftShortcuts.count)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 2)
                                }

                                Spacer()

                                Button("Reset") {
                                    draftShortcuts = ShortcutStore.defaultShortcuts
                                    editingIndex = min(editingIndex, max(0, draftShortcuts.count - 1))
                                }
                                .buttonStyle(.borderless)

                                Button("Save") { commitEdits() }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isSaveDisabled)
                            }
                        }
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
        editingIndex = min(editingIndex, max(0, cleaned.count - 1))
        isEditing = false
        focusedField = nil
    }

    private func pasteIntoFocusedField() {
        guard draftShortcuts.indices.contains(editingIndex),
              let pasted = NSPasteboard.general.string(forType: .string) else {
            return
        }

        switch focusedField {
        case .label:
            draftShortcuts[editingIndex].label = pasted
        case .command:
            draftShortcuts[editingIndex].command = pasted
        case .none:
            break
        }
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

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

                HStack(alignment: .center, spacing: 12) {
                    Button(action: onRefresh) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                            Text("Refresh Now")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .frame(minWidth: 120)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Interval")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        Picker("", selection: $selectedInterval) {
                            ForEach(options, id: \.value) { option in
                                Text(option.label).tag(option.value)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
            }
        }
        .frame(width: 320)
    }
}

struct ShortcutCopyView: View {
    private enum Shortcut: String, CaseIterable, Identifiable {
        case sonnet46
        case opus46
        case sandbox
        case allowPerms

        var id: String { rawValue }

        var label: String {
            switch self {
            case .sonnet46:  return "Sonnet 4.6"
            case .opus46:    return "Opus 4.6"
            case .sandbox:   return "Sandbox"
            case .allowPerms:return "Dangerous Mode"
            }
        }

        var command: String {
            switch self {
            case .sonnet46:   return "/model claude-sonnet-4-6"
            case .opus46:     return "/model claude-opus-4-6"
            case .sandbox:    return "/sandbox"
            case .allowPerms: return "claude --dangerously-skip-permissions"
            }
        }
    }

    @State private var selected: Shortcut = .sonnet46
    @State private var copied = false

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
                }

                Text("Paste directly in your terminal to switch models or modes.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                ], spacing: 8) {
                    ForEach(Shortcut.allCases) { option in
                        Button(action: {
                            selected = option
                            copySelected()
                        }) {
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
        .frame(width: 320)
    }

    private func copySelected() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selected.command, forType: .string)

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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

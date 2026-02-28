import Combine
import Foundation

struct ShortcutItem: Identifiable, Codable, Equatable {
    let id: UUID
    var label: String
    var command: String

    init(id: UUID = UUID(), label: String, command: String) {
        self.id = id
        self.label = label
        self.command = command
    }
}

final class ShortcutStore: ObservableObject {
    @Published private(set) var shortcuts: [ShortcutItem]

    private let fileURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = ShortcutStore.makeFileURL(fileManager: fileManager)
        self.shortcuts = ShortcutStore.defaultShortcuts
        load()
    }

    func update(_ newShortcuts: [ShortcutItem]) {
        shortcuts = newShortcuts
        save(shortcuts)
    }

    func resetToDefaults() {
        update(ShortcutStore.defaultShortcuts)
    }

    // MARK: - Persistence

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            save(shortcuts)
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([ShortcutItem].self, from: data)
            if decoded.isEmpty {
                save(shortcuts)
            } else {
                shortcuts = decoded
            }
        } catch {
            save(shortcuts)
        }
    }

    private func save(_ shortcuts: [ShortcutItem]) {
        do {
            try ensureConfigDirectory()
            let data = try JSONEncoder().encode(shortcuts)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // If save fails, keep in-memory values.
        }
    }

    private func ensureConfigDirectory() throws {
        let dir = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
    }

    private static func makeFileURL(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ClaudeUsageMonitor", isDirectory: true)
            .appendingPathComponent("shortcuts.json")
    }

    static let defaultShortcuts: [ShortcutItem] = [
        ShortcutItem(label: "Sonnet 4.6", command: "/model claude-sonnet-4-6"),
        ShortcutItem(label: "Opus 4.6", command: "/model claude-opus-4-6"),
        ShortcutItem(label: "Sandbox", command: "/sandbox"),
        ShortcutItem(label: "Clear current session", command: "/clear"),
        ShortcutItem(label: "Dangerous Mode", command: "claude --dangerously-skip-permissions"),
    ]
}

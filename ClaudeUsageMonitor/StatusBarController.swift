import AppKit
import SwiftUI

class StatusBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu!
    private var refreshTimer: Timer?
    private let service = AnthropicService()
    private var loginWindow: NSWindow?

    @Published var limits: [UsageLimit] = []
    @Published var refreshInterval: TimeInterval = 600

    /// Dynamic menu items inserted above the separator
    private var usageMenuItems: [NSMenuItem] = []
    private var usageSeparator: NSMenuItem!

    // MARK: - Setup

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "CC--"
        statusItem?.button?.font  = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)

        buildMenu()

        if KeychainManager.shared.getTokens() != nil {
            startAutoRefresh()
            Task { await refreshUsage() }
        } else {
            showLoginWindow()
        }
    }

    func cleanup() { refreshTimer?.invalidate() }

    // MARK: - Menu

    private func buildMenu() {
        menu = NSMenu()

        usageSeparator = NSMenuItem.separator()
        menu.addItem(usageSeparator)

        let refreshItem = NSMenuItem(title: "Refresh Now",
                                     action: #selector(handleRefreshNow),
                                     keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(handleOpenSettings),
                                      keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    @objc private func handleRefreshNow() { Task { await refreshUsage() } }

    @objc private func handleOpenSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Data refresh

    func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.refreshUsage() }
        }
    }

    func refreshUsage() async {
        guard let tokens = KeychainManager.shared.getTokens() else {
            await MainActor.run { showLoginWindow() }
            return
        }
        do {
            let newLimits = try await service.fetchUsage(tokens: tokens)
            await MainActor.run {
                limits = newLimits
                applyLimitsToDisplay(newLimits)
            }
        } catch {
            await MainActor.run { applyErrorToDisplay(error) }
        }
    }

    // MARK: - Display helpers (call on main thread)

    private func applyLimitsToDisplay(_ limits: [UsageLimit]) {
        // Status bar: prefer session (five_hour) limit; fall back to first
        let primary = limits.first(where: { $0.type == .fiveHour }) ?? limits.first
        statusItem?.button?.title = primary.map { "CC-\($0.percentage)%" } ?? "CC--"

        rebuildUsageItems(limits)
    }

    private func applyErrorToDisplay(_ error: Error) {
        statusItem?.button?.title = "--% ⚠"
        let item = NSMenuItem(title: "Error: \(error.localizedDescription)",
                              action: nil, keyEquivalent: "")
        item.isEnabled = false
        rebuildUsageItems(with: [item])

        if case AnthropicError.invalidToken = error { showLoginWindow() }
    }

    private func rebuildUsageItems(_ limits: [UsageLimit]) {
        let items: [NSMenuItem] = limits.isEmpty
            ? [makeDisabledItem("No usage data")]
            : limits.map { limit in
                var title = "\(limit.type.displayName): \(limit.percentage)%"
                if let reset = limit.resetsAt {
                    let secs = reset.timeIntervalSinceNow
                    if secs > 0 {
                        let h = Int(secs / 3600)
                        let m = Int(secs.truncatingRemainder(dividingBy: 3600) / 60)
                        title += " · resets in " + (h > 0 ? "\(h)h \(m)m" : "\(m)m")
                    } else {
                        title += " · resetting…"
                    }
                }
                return makeDisabledItem(title)
            }
        rebuildUsageItems(with: items)
    }

    private func rebuildUsageItems(with items: [NSMenuItem]) {
        usageMenuItems.forEach { menu.removeItem($0) }
        usageMenuItems = items
        let idx = menu.index(of: usageSeparator)
        items.reversed().forEach { menu.insertItem($0, at: idx) }
    }

    private func makeDisabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Login window

    func showLoginWindow() {
        guard loginWindow == nil else {
            loginWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = LoginView {
            self.loginWindow?.close()
            self.loginWindow = nil
            self.startAutoRefresh()
            Task { await self.refreshUsage() }
        }
        let win = NSWindow(contentViewController: NSHostingController(rootView: view))
        win.title = "Claude Usage Monitor"
        win.styleMask = [.titled, .closable]
        win.setContentSize(NSSize(width: 420, height: 320))
        win.center()
        win.isReleasedWhenClosed = false
        loginWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Settings actions

    func setRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = interval
        startAutoRefresh()
    }

    func logout() {
        KeychainManager.shared.deleteTokens()
        refreshTimer?.invalidate()
        limits = []
        statusItem?.button?.title = "CC--"
        rebuildUsageItems([])
        showLoginWindow()
    }
}

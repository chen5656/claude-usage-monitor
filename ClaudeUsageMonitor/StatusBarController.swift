import AppKit
import SwiftUI

class StatusBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu!
    private var refreshTimer: Timer?
    private let service = AnthropicService()
    private var loginWindow: NSWindow?

    @Published var limits: [UsageLimit] = []
    @Published var refreshInterval: TimeInterval = {
        let stored = UserDefaults.standard.double(forKey: "refreshInterval")
        return stored > 0 ? stored : 300
    }()

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
        menu.autoenablesItems = false

        usageSeparator = NSMenuItem.separator()
        menu.addItem(usageSeparator)

        // Refresh controls (button + interval picker)
        let intervalBinding = Binding<TimeInterval>(
            get: { self.refreshInterval },
            set: { newValue in
                self.refreshInterval = newValue
                UserDefaults.standard.set(newValue, forKey: "refreshInterval")
                self.startAutoRefresh()
            }
        )
        let intervalView = RefreshIntervalView(selectedInterval: intervalBinding) {
            Task { await self.refreshUsage() }
        }
        let refreshHostingView = NSHostingView(rootView: intervalView)
        refreshHostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 110)
        let refreshItem = NSMenuItem()
        refreshItem.view = refreshHostingView
        menu.addItem(refreshItem)
        menu.addItem(.separator())

        let shortcutView = ShortcutCopyView()
        let shortcutHostingView = NSHostingView(rootView: shortcutView)
        shortcutHostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 170)
        let shortcutItem = NSMenuItem()
        shortcutItem.view = shortcutHostingView
        menu.addItem(shortcutItem)
        menu.addItem(.separator())

        let logoutItem = NSMenuItem(title: "Log Out",
                                    action: #selector(handleLogOut),
                                    keyEquivalent: "")
        logoutItem.target = self
        logoutItem.isEnabled = true
        menu.addItem(logoutItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.isEnabled = true
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    @objc private func handleLogOut() { logout() }

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
                        let d = Int(secs / 86400)
                        let h = Int(secs.truncatingRemainder(dividingBy: 86400) / 3600)
                        let m = Int(secs.truncatingRemainder(dividingBy: 3600) / 60)
                        if d > 0 {
                            title += " · resets in \(d)d \(h)h \(m)m"
                        } else if h > 0 {
                            title += " · resets in \(h)h \(m)m"
                        } else {
                            title += " · resets in \(m)m"
                        }
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

    func logout() {
        KeychainManager.shared.deleteTokens()
        refreshTimer?.invalidate()
        limits = []
        statusItem?.button?.title = "CC--"
        rebuildUsageItems([])
        showLoginWindow()
    }
}

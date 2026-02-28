import AppKit
import SwiftUI

class StatusBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu!
    private var refreshTimer: Timer?
    private let service = AnthropicService()
    private var loginWindow: NSWindow?
    private let menuCardWidth: CGFloat = 320

    @Published var limits: [UsageLimit] = []
    @Published var refreshInterval: TimeInterval = {
        let stored = UserDefaults.standard.double(forKey: "refreshInterval")
        return stored > 0 ? stored : 350
    }()

    /// Dynamic menu items inserted above the separator
    private var usageMenuItems: [NSMenuItem] = []
    private var usageSeparator: NSMenuItem!
    private var authMenuItem: NSMenuItem!

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
        let refreshItem = makeHostingMenuItem(intervalView)
        menu.addItem(refreshItem)

        let shortcutView = ShortcutCopyView()
        let shortcutItem = makeHostingMenuItem(shortcutView)
        menu.addItem(shortcutItem)
        menu.addItem(.separator())

        let isLoggedIn = KeychainManager.shared.getTokens() != nil
        authMenuItem = NSMenuItem(
            title: isLoggedIn ? "Log Out" : "Log In",
            action: isLoggedIn ? #selector(handleLogOut) : #selector(handleLogIn),
            keyEquivalent: ""
        )
        authMenuItem.target = self
        authMenuItem.isEnabled = true
        menu.addItem(authMenuItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.isEnabled = true
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    @objc private func handleLogOut() { logout() }
    @objc private func handleLogIn() { showLoginWindow() }

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
        let item = makeInfoItem("Error: \(error.localizedDescription)", color: .systemOrange)
        rebuildUsageItems(with: [item])

        if case AnthropicError.invalidToken = error { showLoginWindow() }
    }

    private func rebuildUsageItems(_ limits: [UsageLimit]) {
        let items: [NSMenuItem] = limits.isEmpty
            ? [makeInfoItem("No usage data")]
            : limits.map { limit in
                var detail = "\(limit.percentage)%"
                if let reset = limit.resetsAt {
                    let secs = reset.timeIntervalSinceNow
                    if secs > 0 {
                        let d = Int(secs / 86400)
                        let h = Int(secs.truncatingRemainder(dividingBy: 86400) / 3600)
                        let m = Int(secs.truncatingRemainder(dividingBy: 3600) / 60)
                        if d > 0 {
                            detail += " · resets in \(d)d \(h)h \(m)m"
                        } else if h > 0 {
                            detail += " · resets in \(h)h \(m)m"
                        } else {
                            detail += " · resets in \(m)m"
                        }
                    } else {
                        detail += " · resetting…"
                    }
                }
                return makeUsageItem(label: limit.type.displayName, detail: detail)
            }
        rebuildUsageItems(with: items)
    }

    private func rebuildUsageItems(with items: [NSMenuItem]) {
        usageMenuItems.forEach { menu.removeItem($0) }
        usageMenuItems = items
        let idx = menu.index(of: usageSeparator)
        items.reversed().forEach { menu.insertItem($0, at: idx) }
    }

    private func makeInfoItem(_ title: String, color: NSColor = .secondaryLabelColor) -> NSMenuItem {
        let item = NSMenuItem()
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = color
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail

        let container = NSView(frame: NSRect(x: 0, y: 0, width: menuCardWidth, height: 24))
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        item.view = container
        return item
    }

    private func makeUsageItem(label: String, detail: String) -> NSMenuItem {
        let item = NSMenuItem()
        let titleField = NSTextField(labelWithString: label)
        titleField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail

        let detailField = NSTextField(labelWithString: detail)
        detailField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        detailField.textColor = .secondaryLabelColor
        detailField.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [titleField, detailField])
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: menuCardWidth, height: 24))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        item.view = container
        return item
    }

    private func makeHostingMenuItem<V: View>(_ rootView: V) -> NSMenuItem {
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: menuCardWidth, height: 1)
        hostingView.layoutSubtreeIfNeeded()
        let height = hostingView.fittingSize.height
        hostingView.frame = NSRect(x: 0, y: 0, width: menuCardWidth, height: height)
        let item = NSMenuItem()
        item.view = hostingView
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
            self.authMenuItem.title = "Log Out"
            self.authMenuItem.action = #selector(self.handleLogOut)
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
        authMenuItem.title = "Log In"
        authMenuItem.action = #selector(handleLogIn)
    }
}

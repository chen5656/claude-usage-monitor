import AppKit
import SwiftUI

class StatusBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu!
    private var refreshTimer: Timer?
    private let anthropicService = AnthropicService()
    private var loginWindow: NSWindow?

    @Published var usageData: UsageData?
    @Published var refreshInterval: TimeInterval = 600  // 10 minutes default

    // Menu items updated after each refresh
    private var usageMenuItem   = NSMenuItem()
    private var tokensMenuItem  = NSMenuItem()
    private var resetMenuItem   = NSMenuItem()

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.title = "CC--"
            button.font  = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        }

        buildMenu()

        if KeychainManager.shared.getAPIKey() != nil {
            startAutoRefresh()
            Task { await refreshUsage() }
        } else {
            showLoginWindow()
        }
    }

    func cleanup() {
        refreshTimer?.invalidate()
    }

    // MARK: - Menu

    private func buildMenu() {
        menu = NSMenu()

        usageMenuItem.isEnabled  = false
        tokensMenuItem.isEnabled = false
        resetMenuItem.isEnabled  = false

        usageMenuItem.title  = "Usage: --"
        tokensMenuItem.title = "Tokens: --"
        resetMenuItem.title  = "Reset: --"

        menu.addItem(usageMenuItem)
        menu.addItem(tokensMenuItem)
        menu.addItem(resetMenuItem)
        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(handleRefreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(handleOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func handleRefreshNow() {
        Task { await refreshUsage() }
    }

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
        guard let apiKey = KeychainManager.shared.getAPIKey() else {
            await MainActor.run { showLoginWindow() }
            return
        }

        do {
            let data = try await anthropicService.fetchUsage(apiKey: apiKey)
            await MainActor.run {
                usageData = data
                applyUsageToDisplay(data)
            }
        } catch {
            await MainActor.run { applyErrorToDisplay(error) }
        }
    }

    // MARK: - Display updates (must be called on main thread)

    private func applyUsageToDisplay(_ data: UsageData) {
        let pct = Int(data.usagePercentage.rounded())
        statusItem?.button?.title = "CC-\(pct)%"

        usageMenuItem.title  = "Usage: \(pct)%"

        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        let used = fmt.string(from: NSNumber(value: data.tokensUsed)) ?? "\(data.tokensUsed)"
        let limit = fmt.string(from: NSNumber(value: data.tokensLimit)) ?? "\(data.tokensLimit)"
        tokensMenuItem.title = "Tokens: \(used) / \(limit)"

        if let reset = data.resetAt {
            let interval = reset.timeIntervalSinceNow
            if interval > 0 {
                let h = Int(interval / 3600)
                let m = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
                resetMenuItem.title = h > 0
                    ? "Reset in: \(h)h \(m)m"
                    : "Reset in: \(m)m"
            } else {
                resetMenuItem.title = "Reset: Now"
            }
        } else {
            resetMenuItem.title = "Reset: --"
        }
    }

    private func applyErrorToDisplay(_ error: Error) {
        statusItem?.button?.title = "--% ⚠"
        usageMenuItem.title  = "Error: \(error.localizedDescription)"
        tokensMenuItem.title = "Tokens: --"
        resetMenuItem.title  = "Reset: --"

        if case AnthropicError.invalidAPIKey = error {
            showLoginWindow()
        }
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

        let vc = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: vc)
        win.title = "Claude Usage Monitor – Setup"
        win.styleMask = [.titled, .closable]
        win.setContentSize(NSSize(width: 420, height: 300))
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
        KeychainManager.shared.deleteAPIKey()
        refreshTimer?.invalidate()
        usageData = nil
        statusItem?.button?.title = "CC--"
        usageMenuItem.title  = "Usage: --"
        tokensMenuItem.title = "Tokens: --"
        resetMenuItem.title  = "Reset: --"
        showLoginWindow()
    }
}

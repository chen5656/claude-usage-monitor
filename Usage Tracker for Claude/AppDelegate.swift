import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    let statusBarController = StatusBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController.setup()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController.cleanup()
    }
}

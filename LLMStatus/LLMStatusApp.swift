import AppKit
import SwiftUI

@main
struct LLMStatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible windows — everything runs from the menu bar
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings()
        let monitor = StatusMonitor()
        let network = NetworkMonitor()

        monitor.notificationsEnabled = settings.notificationsEnabled
        monitor.notifyProviderID = settings.menuBarProvider
        monitor.disabledProviderIDs = settings.disabledProviderIDs
        monitor.startPolling(interval: settings.refreshInterval)
        network.start()

        statusBarController = StatusBarController(
            monitor: monitor,
            settings: settings,
            network: network
        )
    }
}

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
        terminateOtherInstances()

        let settings = AppSettings()
        let monitor = StatusMonitor()
        let network = NetworkMonitor()

        settings.reconcileLaunchAtLogin()

        monitor.notificationsEnabled = settings.notificationsEnabled
        monitor.notifyProviderID = settings.menuBarProvider

        // Request notification permission on first launch
        Task { await monitor.notificationManager.requestPermission() }
        monitor.disabledProviderIDs = settings.disabledProviderIDs

        // Restore watched components from persisted settings
        let watchedMap = settings.watchedComponents
        if !watchedMap.isEmpty {
            var map: [String: String] = [:]
            for entry in watchedMap.split(separator: ",") {
                let parts = entry.split(separator: ":", maxSplits: 1)
                if parts.count == 2 { map[String(parts[0])] = String(parts[1]) }
            }
            monitor.watchedComponentMap = map
        }

        if !settings.providerOrderIDs.isEmpty {
            monitor.reorderProviders(orderedIDs: settings.providerOrderIDs)
        }
        monitor.startPolling(interval: settings.refreshInterval)
        network.start()

        statusBarController = StatusBarController(
            monitor: monitor,
            settings: settings,
            network: network
        )
    }

    /// Same bundle ID can be launched from /Applications and from .build/app;
    /// keep a single menu bar extra by replacing any older instance.
    private func terminateOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID }
        for app in others {
            app.forceTerminate()
            let deadline = Date().addingTimeInterval(1)
            while !app.isTerminated && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }
}

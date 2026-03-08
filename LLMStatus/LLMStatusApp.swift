import SwiftUI

@main
struct LLMStatusApp: App {
    @State private var monitor = StatusMonitor()
    @State private var settings = AppSettings()

    var body: some Scene {
        MenuBarExtra {
            StatusPopoverView(monitor: monitor, settings: settings)
                .onChange(of: settings.refreshInterval) { _, newInterval in
                    monitor.startPolling(interval: newInterval)
                }
                .onChange(of: settings.notificationsEnabled) { _, enabled in
                    monitor.notificationsEnabled = enabled
                }
                .task {
                    monitor.notificationsEnabled = settings.notificationsEnabled
                    await monitor.notificationManager.requestPermission()
                    monitor.startPolling(interval: settings.refreshInterval)
                }
        } label: {
            Image(systemName: monitor.aggregatedStatus.sfSymbol)
        }
        .menuBarExtraStyle(.window)
        .defaultSize(width: 320, height: 400)
    }
}

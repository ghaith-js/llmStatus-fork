import AppKit
import SwiftUI

@main
struct LLMStatusApp: App {
    @State private var monitor: StatusMonitor
    @State private var settings = AppSettings()

    init() {
        let settings = AppSettings()
        let monitor = StatusMonitor()
        monitor.notificationsEnabled = settings.notificationsEnabled
        monitor.notifyProviderID = settings.menuBarProvider
        monitor.disabledProviderIDs = settings.disabledProviderIDs
        monitor.startPolling(interval: settings.refreshInterval)
        _monitor = State(initialValue: monitor)
        _settings = State(initialValue: settings)
    }

    var body: some Scene {
        MenuBarExtra {
            StatusPopoverView(monitor: monitor, settings: settings)
                .onChange(of: settings.refreshInterval) { _, newInterval in
                    monitor.startPolling(interval: newInterval)
                }
                .onChange(of: settings.notificationsEnabled) { _, enabled in
                    monitor.notificationsEnabled = enabled
                }
                .onChange(of: settings.menuBarProvider) { _, providerID in
                    monitor.notifyProviderID = providerID
                }
                .onChange(of: settings.disabledProviders) { _, _ in
                    monitor.disabledProviderIDs = settings.disabledProviderIDs
                }
        } label: {
            let status = monitor.menuBarStatus(for: settings.menuBarProvider)
            let label = monitor.menuBarLabel(for: settings.menuBarProvider)
            HStack(spacing: 6) {
                Image(nsImage: coloredDot(status.nsColor))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .menuBarExtraStyle(.window)
        .defaultSize(width: 320, height: 400)
    }

    /// Draws a colored circle as a non-template NSImage so macOS won't strip the color.
    private func coloredDot(_ color: NSColor) -> NSImage {
        let size = NSSize(width: 11, height: 11)
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

import AppKit
import SwiftUI

extension Notification.Name {
    static let showSettings = Notification.Name("showSettings")
}

/// Manages the NSStatusItem with left-click (popover) and right-click (context menu).
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private let popover = NSPopover()
    private var monitor: StatusMonitor
    private var settings: AppSettings
    private var network: NetworkMonitor
    private var iconTimer: Timer?

    init(monitor: StatusMonitor, settings: AppSettings, network: NetworkMonitor) {
        self.monitor = monitor
        self.settings = settings
        self.network = network
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        setupPopover()
        setupButton()
        updateIcon()

        // Poll icon state — lightweight since it only redraws on change
        iconTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateIcon()
        }
    }

    private func setupPopover() {
        let m = monitor
        let s = settings
        let n = network
        let view = StatusPopoverView(monitor: m, settings: s, network: n)
            .onChange(of: s.refreshInterval) { _, newInterval in
                m.startPolling(interval: newInterval)
            }
            .onChange(of: s.notificationsEnabled) { _, enabled in
                m.notificationsEnabled = enabled
            }
            .onChange(of: s.menuBarProvider) { _, providerID in
                m.notifyProviderID = providerID
            }
            .onChange(of: s.disabledProviders) { _, _ in
                m.disabledProviderIDs = s.disabledProviderIDs
            }

        popover.contentViewController = NSHostingController(rootView: view)
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
    }

    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshAction), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(settingsAction), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit LLM Status", action: #selector(quitAction), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Reset so left-click still opens popover
        statusItem.menu = nil
    }

    @objc private func refreshAction() {
        Task { await monitor.forceRefresh() }
    }

    @objc private func settingsAction() {
        // Open popover then notify it to show settings
        if !popover.isShown, let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
        NotificationCenter.default.post(name: .showSettings, object: nil)
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Icon

    private var lastIconStatus: ServiceStatus?
    private var lastIconLabel: String?

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let status = monitor.menuBarStatus(for: settings.menuBarProvider)
        let label = monitor.menuBarLabel(for: settings.menuBarProvider)

        // Skip redraw if nothing changed
        guard status != lastIconStatus || label != lastIconLabel else { return }
        lastIconStatus = status
        lastIconLabel = label

        button.image = tintedMenuBarIcon(status.nsColor)
        button.title = " \(label)"
        button.imagePosition = .imageLeading
    }

    private func tintedMenuBarIcon(_ tint: NSColor) -> NSImage {
        guard let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "pdf"),
              let template = NSImage(contentsOf: url) else {
            return fallbackDot(tint)
        }

        let height: CGFloat = 18
        let aspect = template.size.width / template.size.height
        let size = NSSize(width: height * aspect, height: height)

        let image = NSImage(size: size, flipped: false) { rect in
            template.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        return image
    }

    private func fallbackDot(_ color: NSColor) -> NSImage {
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

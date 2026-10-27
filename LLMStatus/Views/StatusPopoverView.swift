import SwiftUI

struct StatusPopoverView: View {
    let monitor: StatusMonitor
    let settings: AppSettings
    let network: NetworkMonitor
    @State private var showingSettings = false
    /// Provider whose components are shown in place of the gallery.
    @State private var selectedProviderID: String?

    private var selectedProvider: ServiceProvider? {
        monitor.enabledProviders.first { $0.id == selectedProviderID }
    }

    private let galleryColumns = [
        GridItem(.flexible(), spacing: 8, alignment: .top),
        GridItem(.flexible(), spacing: 8, alignment: .top),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showingSettings {
                // Settings header
                HStack {
                    Button {
                        showingSettings = false
                        // Refresh providers that may have been newly enabled
                        Task { await monitor.refreshIfNeeded() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .focusable(false)

                    Text("Settings")
                        .font(.headline)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider()

                SettingsView(settings: settings, monitor: monitor)
            } else if let provider = selectedProvider {
                HStack {
                    Button {
                        selectedProviderID = nil
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .focusable(false)

                    Text("Status")
                        .font(.headline)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider()

                ScrollView {
                    ProviderDetailView(provider: provider)
                        .padding(12)
                }
            } else {
                // Header
                HStack {
                    MenuBarIconView(status: monitor.menuBarStatus(for: settings.menuBarProvider))
                    Text("LLM Status")
                        .font(.headline)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider()

                // Offline banner
                if !network.isConnected {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.slash")
                            .font(.caption)
                        Text("No connection — status may be outdated")
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                    Divider()
                }

                // Subscription usage + provider list share one scroll area (the usage fold can grow)
                ScrollView {
                    if !monitor.usage.visibleUsages.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(monitor.usage.visibleUsages) { usage in
                                UsageRowView(usage: usage)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                        Divider()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Status")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: galleryColumns, spacing: 8) {
                            ForEach(monitor.enabledProviders) { provider in
                                ProviderCardView(provider: provider)
                                    .onTapGesture { selectedProviderID = provider.id }
                            }
                        }
                    }
                    .padding(12)
                }

                Divider()

                // Footer
                HStack(spacing: 12) {
                    Button {
                        Task { await monitor.forceRefresh() }
                    } label: {
                        HStack(spacing: 4) {
                            if monitor.isPolling {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Refresh")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .disabled(monitor.isRefreshing)

                    if let lastCheck = monitor.lastFullCheck {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(Self.relativeTime(from: lastCheck))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gear")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Text("Quit")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 320)
        .focusable(false)
        .focusEffectDisabled()
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            selectedProviderID = nil
            showingSettings = true
        }
    }

    static func relativeTime(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "Just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }
}

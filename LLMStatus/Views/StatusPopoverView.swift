import SwiftUI

struct StatusPopoverView: View {
    let monitor: StatusMonitor
    let settings: AppSettings
    let network: NetworkMonitor
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showingSettings {
                // Settings header
                HStack {
                    Button {
                        showingSettings = false
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)

                    Text("Settings")
                        .font(.headline)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider()

                SettingsView(settings: settings, monitor: monitor)
            } else {
                // Header
                HStack {
                    Image(systemName: monitor.menuBarStatus(for: settings.menuBarProvider).sfSymbol)
                        .foregroundStyle(monitor.menuBarStatus(for: settings.menuBarProvider).color)
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

                // Provider list (enabled only)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(monitor.enabledProviders) { provider in
                            ServiceRowView(provider: provider)
                                .padding(.horizontal, 12)

                            if provider.id != monitor.enabledProviders.last?.id {
                                Divider()
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Divider()

                // Footer
                HStack(spacing: 12) {
                    Button {
                        Task { await monitor.forceRefresh() }
                    } label: {
                        HStack(spacing: 4) {
                            if monitor.isRefreshing {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Refresh")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .disabled(monitor.isRefreshing)

                    if let lastCheck = monitor.lastFullCheck {
                        Text(lastCheck, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gear")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Text("Quit")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 320)
    }

}

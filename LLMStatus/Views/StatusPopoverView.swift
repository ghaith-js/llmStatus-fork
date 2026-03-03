import SwiftUI

struct StatusPopoverView: View {
    let monitor: StatusMonitor
    let settings: AppSettings
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: monitor.aggregatedStatus.sfSymbol)
                    .foregroundStyle(monitor.aggregatedStatus.color)
                Text("LLM Status")
                    .font(.headline)

                Spacer()

                Text(lastRefreshText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Provider list
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(monitor.providers) { provider in
                        ServiceRowView(provider: provider)
                            .padding(.horizontal, 12)

                        if provider.id != monitor.providers.last?.id {
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
                    Task { await monitor.fetchAllStatuses() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Spacer()

                Button {
                    showingSettings.toggle()
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
        .frame(width: 320)
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: settings)
        }
    }

    private var lastRefreshText: String {
        let latest = monitor.providers.compactMap(\.lastChecked).max()
        guard let date = latest else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

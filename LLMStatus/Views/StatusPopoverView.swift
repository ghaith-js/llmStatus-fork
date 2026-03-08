import SwiftUI

struct StatusPopoverView: View {
    let monitor: StatusMonitor
    let settings: AppSettings
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

                SettingsView(settings: settings, providers: monitor.providers)
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

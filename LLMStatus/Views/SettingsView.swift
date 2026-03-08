import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var monitor: StatusMonitor
    @State private var orderedProviders: [ServiceProvider] = []

    var body: some View {
        Form {
            // Menu bar icon source — only enabled providers
            Picker("Menu bar icon", selection: $settings.menuBarProvider) {
                Text("All providers").tag("all")
                ForEach(orderedProviders.filter { settings.isProviderEnabled($0.id) }) { provider in
                    Text(provider.name).tag(provider.id)
                }
            }

            // Refresh interval
            Picker("Refresh interval", selection: $settings.refreshInterval) {
                ForEach(AppSettings.intervalOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }

            // Launch at login
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
                .onChange(of: settings.launchAtLogin) { _, enabled in
                    if enabled {
                        try? SMAppService.mainApp.register()
                    } else {
                        try? SMAppService.mainApp.unregister()
                    }
                }

            // Notifications
            Toggle("Notifications enabled", isOn: $settings.notificationsEnabled)

            // Providers — drag & drop reorder + enable/disable
            Section("Providers") {
                List {
                    ForEach(orderedProviders) { provider in
                        HStack {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.tertiary)
                                .font(.caption)

                            Toggle(provider.name, isOn: Binding(
                                get: { settings.isProviderEnabled(provider.id) },
                                set: { _ in
                                    settings.toggleProvider(provider.id)
                                    monitor.disabledProviderIDs = settings.disabledProviderIDs
                                }
                            ))
                        }
                    }
                    .onMove { from, to in
                        orderedProviders.move(fromOffsets: from, toOffset: to)
                        let ids = orderedProviders.map(\.id)
                        settings.providerOrderIDs = ids
                        monitor.reorderProviders(orderedIDs: ids)
                    }
                }
                .listStyle(.plain)
                .frame(height: CGFloat(orderedProviders.count) * 28)
            }

            // Logs
            Section {
                Button("Open logs folder") {
                    let logsDir = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Library/Logs/LLMStatus")
                    NSWorkspace.shared.open(logsDir)
                }
            }

            // App version
            Section {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // Initialize with current order
            let savedOrder = settings.providerOrderIDs
            if savedOrder.isEmpty {
                orderedProviders = monitor.providers
            } else {
                let lookup = Dictionary(uniqueKeysWithValues: monitor.providers.map { ($0.id, $0) })
                let fromOrder = savedOrder.compactMap { lookup[$0] }
                let remaining = monitor.providers.filter { p in !savedOrder.contains(p.id) }
                orderedProviders = fromOrder + remaining
            }
        }
    }
}

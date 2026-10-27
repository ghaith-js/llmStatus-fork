import SwiftUI

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

            if let message = settings.launchAtLoginStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                    }
                    .onMove { from, to in
                        orderedProviders.move(fromOffsets: from, toOffset: to)
                        let ids = orderedProviders.map(\.id)
                        settings.providerOrderIDs = ids
                        monitor.reorderProviders(orderedIDs: ids)
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 26)
                .frame(height: CGFloat(orderedProviders.count) * 26)
                .scrollDisabled(true)
            }

            // Subscription usage (weekly limits read from the local Claude Code / Codex logins)
            Section("Subscription usage") {
                ForEach(SubscriptionUsage.Kind.allCases, id: \.self) { kind in
                    Toggle(kind.name, isOn: Binding(
                        get: { settings.isUsageShown(kind) },
                        set: { shown in
                            settings.setUsageShown(shown, for: kind)
                            monitor.usage.enabledKinds = settings.enabledUsageKinds
                            if shown { Task { await monitor.usage.refresh() } }
                        }
                    ))
                }
            }

            RemoteHostsSection(settings: settings, usage: monitor.usage)

            // Watched component per provider
            Section("Focus component") {
                ForEach(orderedProviders.filter { settings.isProviderEnabled($0.id) && !$0.components.isEmpty }) { provider in
                    Picker(provider.shortName, selection: Binding(
                        get: { settings.watchedComponent(for: provider.id) },
                        set: { newValue in
                            settings.setWatchedComponent(newValue, for: provider.id)
                            monitor.watchedComponentMap = buildWatchedMap()
                        }
                    )) {
                        Text("All").tag("all")
                        ForEach(allComponentNames(for: provider), id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                }
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
            settings.refreshLaunchAtLoginStatus()
            orderedProviders = monitor.orderedProviders(by: settings.providerOrderIDs)
            monitor.watchedComponentMap = buildWatchedMap()
        }
    }

    /// Flat list of component names (groups + children) for a provider
    private func allComponentNames(for provider: ServiceProvider) -> [String] {
        var names: [String] = []
        for component in provider.components {
            names.append(component.name)
            for child in component.children {
                names.append(child.name)
            }
        }
        return names
    }

    /// Build the watched component map from settings
    private func buildWatchedMap() -> [String: String] {
        var map: [String: String] = [:]
        for provider in orderedProviders {
            let watched = settings.watchedComponent(for: provider.id)
            if watched != "all" {
                map[provider.id] = watched
            }
        }
        return map
    }
}

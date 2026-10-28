import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var monitor: StatusMonitor
    @State private var orderedProviders: [ServiceProvider] = []
    @State private var tab: Tab = .general

    enum Tab: String, CaseIterable {
        case general = "General"
        case providers = "Providers"
        case usage = "Usage"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Form {
                switch tab {
                case .general:
                    // Menu bar icon source — only enabled providers
                    Picker("Menu bar icon", selection: $settings.menuBarProvider) {
                        Text("All providers").tag("all")
                        ForEach(orderedProviders.filter { settings.isProviderEnabled($0.id) }) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }

                    // What the menu bar shows next to the cloud
                    Picker("Menu bar shows", selection: Binding(
                        get: { settings.menuBarIndicator },
                        set: { settings.menuBarIndicator = $0 }
                    )) {
                        ForEach(MenuBarIndicator.allCases) { Text($0.title).tag($0) }
                    }
                    if settings.menuBarIndicator != .status {
                        Toggle("Show the cloud with usage", isOn: Binding(
                            get: { settings.menuBarShowsCloud },
                            set: { settings.menuBarShowsCloud = $0 }
                        ))
                    }
                    if settings.menuBarIndicator == .gauges {
                        Toggle("Percent next to each gauge", isOn: Binding(
                            get: { settings.menuBarGaugeNumbers },
                            set: { settings.menuBarGaugeNumbers = $0 }
                        ))
                    }
                    if settings.menuBarIndicator.needsAccount {
                        Picker("Subscription", selection: Binding(
                            get: { settings.menuBarAccountID },
                            set: { settings.menuBarAccountID = $0 }
                        )) {
                            Text("First with a 5h window").tag(UUID?.none)
                            ForEach(monitor.usage.groups) { group in
                                ForEach(group.accounts.filter(\.enabled)) { account in
                                    Text("\(group.name) · \(account.name)").tag(UUID?.some(account.id))
                                }
                            }
                        }
                    }
                    if settings.menuBarIndicator == .alert {
                        Picker("Show usage from", selection: Binding(
                            get: { settings.menuBarThreshold },
                            set: { settings.menuBarThreshold = $0 }
                        )) {
                            ForEach([50.0, 60, 70, 80, 90], id: \.self) { Text("\(Int($0))% weekly").tag($0) }
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
                case .providers:
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
                case .usage:
                    // Subscriptions shown, by group (this Mac's logins and logins on SSH hosts)
                    UsageAccountsSection(settings: settings, usage: monitor.usage)

                    RemoteHostsSection(settings: settings, usage: monitor.usage)
                }
            }
            .formStyle(.grouped)
        }
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

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var providers: [ServiceProvider] = []

    var body: some View {
        Form {
            // Menu bar icon source — only enabled providers
            Picker("Menu bar icon", selection: $settings.menuBarProvider) {
                Text("All providers").tag("all")
                ForEach(providers.filter { settings.isProviderEnabled($0.id) }) { provider in
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

            // Providers toggle
            Section("Providers") {
                ForEach(providers) { provider in
                    Toggle(provider.name, isOn: Binding(
                        get: { settings.isProviderEnabled(provider.id) },
                        set: { _ in settings.toggleProvider(provider.id) }
                    ))
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
    }
}

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var providers: [ServiceProvider] = []

    var body: some View {
        Form {
            // Menu bar icon source
            Picker("Menu bar icon", selection: $settings.menuBarProvider) {
                Text("All providers").tag("all")
                ForEach(providers) { provider in
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

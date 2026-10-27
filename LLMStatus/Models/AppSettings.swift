import Foundation
import ServiceManagement
import SwiftUI

@Observable
class AppSettings {
    @ObservationIgnored
    @AppStorage("refreshInterval") var refreshInterval: TimeInterval = 60
    @ObservationIgnored
    @AppStorage("launchAtLogin") private var launchAtLoginPreference: Bool = false
    private var launchAtLoginTick = 0
    var launchAtLoginStatusMessage: String?
    @ObservationIgnored
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = true
    @ObservationIgnored
    @AppStorage("menuBarProvider") var menuBarProvider: String = "all"
    @ObservationIgnored
    @AppStorage("disabledProviders") var disabledProviders: String = ""
    /// Triggers SwiftUI re-render when disabled providers change
    private var disabledProvidersTick = 0
    @ObservationIgnored
    @AppStorage("providerOrder") var providerOrder: String = ""
    @ObservationIgnored
    @AppStorage("watchedComponents") var watchedComponents: String = ""
    private var watchedComponentsTick = 0
    @ObservationIgnored
    @AppStorage("hiddenUsage") var hiddenUsage: String = ""
    /// SSH hosts whose Codex usage joins the breakdown, as JSON `[RemoteUsage.Host]`.
    @ObservationIgnored
    @AppStorage("usageSSHHosts") var usageSSHHosts: String = ""
    /// Former comma-separated list of aliases, migrated on first read.
    @ObservationIgnored
    @AppStorage("usageRemoteHosts") var legacyUsageRemoteHosts: String = ""
    private var remoteHostsTick = 0

    var remoteHosts: [RemoteUsage.Host] {
        get {
            _ = remoteHostsTick
            if let hosts = try? JSONDecoder().decode([RemoteUsage.Host].self, from: Data(usageSSHHosts.utf8)) {
                return hosts
            }
            var seen = Set<String>()
            return legacyUsageRemoteHosts.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && seen.insert($0).inserted }
                .map { RemoteUsage.Host(alias: $0) }
        }
        set {
            usageSSHHosts = (try? String(decoding: JSONEncoder().encode(newValue), as: UTF8.self)) ?? ""
            legacyUsageRemoteHosts = ""
            remoteHostsTick += 1
        }
    }
    private var hiddenUsageTick = 0

    var launchAtLogin: Bool {
        get {
            _ = launchAtLoginTick
            return SMAppService.mainApp.status == .enabled
        }
        set {
            setLaunchAtLogin(newValue)
        }
    }

    func reconcileLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        if launchAtLoginPreference, status == .notRegistered || status == .notFound {
            setLaunchAtLogin(true)
        } else {
            updateLaunchAtLoginStatusMessage()
        }
    }

    func refreshLaunchAtLoginStatus() {
        updateLaunchAtLoginStatusMessage()
        launchAtLoginTick += 1
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
                launchAtLoginPreference = true
            } else {
                if SMAppService.mainApp.status != .notRegistered {
                    try SMAppService.mainApp.unregister()
                }
                launchAtLoginPreference = false
            }
        } catch {
            launchAtLoginStatusMessage = "Launch at login could not be updated: \(error.localizedDescription)"
            if enabled {
                launchAtLoginPreference = false
            }
            launchAtLoginTick += 1
            return
        }

        updateLaunchAtLoginStatusMessage()
        launchAtLoginTick += 1
    }

    private func updateLaunchAtLoginStatusMessage() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLoginStatusMessage = nil
        case .notRegistered:
            launchAtLoginStatusMessage = launchAtLoginPreference
                ? "Launch at login is not registered with macOS."
                : nil
        case .requiresApproval:
            launchAtLoginStatusMessage = "Approve LLM Status in System Settings > General > Login Items."
        case .notFound:
            launchAtLoginStatusMessage = "macOS could not find this app bundle for login items."
        @unknown default:
            launchAtLoginStatusMessage = "macOS returned an unknown login item status."
        }
    }

    /// IDs of providers the user has disabled
    var disabledProviderIDs: Set<String> {
        get {
            Set(disabledProviders.split(separator: ",").map(String.init))
        }
        set {
            disabledProviders = newValue.sorted().joined(separator: ",")
        }
    }

    func isProviderEnabled(_ id: String) -> Bool {
        _ = disabledProvidersTick // read to subscribe to changes
        return !disabledProviderIDs.contains(id)
    }

    func toggleProvider(_ id: String) {
        var ids = disabledProviderIDs
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        disabledProviderIDs = ids
        disabledProvidersTick += 1 // trigger re-render
    }

    /// Ordered list of provider IDs (persisted)
    var providerOrderIDs: [String] {
        get {
            let ids = providerOrder.split(separator: ",").map(String.init)
            return ids.isEmpty ? [] : ids
        }
        set {
            providerOrder = newValue.joined(separator: ",")
        }
    }

    // MARK: - Subscription usage

    var hiddenUsageKinds: Set<SubscriptionUsage.Kind> {
        Set(hiddenUsage.split(separator: ",").compactMap { SubscriptionUsage.Kind(rawValue: String($0)) })
    }

    var enabledUsageKinds: Set<SubscriptionUsage.Kind> {
        Set(SubscriptionUsage.Kind.allCases).subtracting(hiddenUsageKinds)
    }

    func isUsageShown(_ kind: SubscriptionUsage.Kind) -> Bool {
        _ = hiddenUsageTick
        return !hiddenUsageKinds.contains(kind)
    }

    func setUsageShown(_ shown: Bool, for kind: SubscriptionUsage.Kind) {
        var kinds = hiddenUsageKinds
        if shown { kinds.remove(kind) } else { kinds.insert(kind) }
        hiddenUsage = kinds.map(\.rawValue).sorted().joined(separator: ",")
        hiddenUsageTick += 1
    }

    // MARK: - Watched components per provider

    /// Get the watched component name for a provider ("all" = overall status)
    func watchedComponent(for providerID: String) -> String {
        _ = watchedComponentsTick
        let map = parseWatchedComponents()
        return map[providerID] ?? "all"
    }

    /// Set the watched component for a provider
    func setWatchedComponent(_ componentName: String, for providerID: String) {
        var map = parseWatchedComponents()
        if componentName == "all" {
            map.removeValue(forKey: providerID)
        } else {
            map[providerID] = componentName
        }
        watchedComponents = map.map { "\($0.key):\($0.value)" }.sorted().joined(separator: ",")
        watchedComponentsTick += 1
    }

    private func parseWatchedComponents() -> [String: String] {
        guard !watchedComponents.isEmpty else { return [:] }
        var map: [String: String] = [:]
        for entry in watchedComponents.split(separator: ",") {
            let parts = entry.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                map[String(parts[0])] = String(parts[1])
            }
        }
        return map
    }

    /// Human-readable interval options for the picker.
    static let intervalOptions: [(label: String, value: TimeInterval)] = [
        ("1 min", 60),
        ("2 min", 120),
        ("5 min", 300),
        ("10 min", 600),
    ]
}

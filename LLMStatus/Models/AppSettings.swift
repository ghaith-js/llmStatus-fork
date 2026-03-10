import Foundation
import SwiftUI

@Observable
class AppSettings {
    @ObservationIgnored
    @AppStorage("refreshInterval") var refreshInterval: TimeInterval = 60
    @ObservationIgnored
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
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

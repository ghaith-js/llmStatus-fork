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

    /// Human-readable interval options for the picker.
    static let intervalOptions: [(label: String, value: TimeInterval)] = [
        ("1 min", 60),
        ("2 min", 120),
        ("5 min", 300),
        ("10 min", 600),
    ]
}

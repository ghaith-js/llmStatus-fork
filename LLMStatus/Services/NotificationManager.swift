import Foundation
import UserNotifications

@Observable
class NotificationManager {
    private struct NotifiedEntry {
        let status: IncidentStatus
        let date: Date
    }

    /// Tracks "providerID-incidentID" → last notified status + timestamp
    private var notifiedIncidents: [String: NotifiedEntry] = [:]

    /// Request notification permission from macOS.
    func requestPermission() async {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Check if we should notify for this incident (new or status changed).
    func shouldNotify(providerID: String, incident: Incident) -> Bool {
        let key = Self.notificationIdentifier(providerID: providerID, incidentID: incident.id)
        guard let entry = notifiedIncidents[key] else {
            return true // never notified
        }
        return entry.status != incident.status // status changed
    }

    /// Mark an incident as notified with its current status.
    func markNotified(providerID: String, incident: Incident) {
        let key = Self.notificationIdentifier(providerID: providerID, incidentID: incident.id)
        notifiedIncidents[key] = NotifiedEntry(status: incident.status, date: Date())
    }

    /// Remove entries older than 24h to prevent unbounded growth.
    func purgeStaleEntries() {
        let cutoff = Date().addingTimeInterval(-86400)
        notifiedIncidents = notifiedIncidents.filter { $0.value.date > cutoff }
    }

    /// Send a macOS notification for an incident.
    func sendIncidentNotification(providerName: String, providerID: String, incident: Incident) async {
        guard shouldNotify(providerID: providerID, incident: incident) else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(providerName) — \(incident.impact.rawValue.capitalized)"
        content.body = incident.name
        content.sound = .default

        let identifier = Self.notificationIdentifier(providerID: providerID, incidentID: incident.id)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        if Bundle.main.bundleIdentifier != nil {
            let center = UNUserNotificationCenter.current()
            try? await center.add(request)
        }

        markNotified(providerID: providerID, incident: incident)
    }

    /// Send a recovery notification when a provider returns to operational.
    func sendRecoveryNotification(providerName: String, providerID: String) async {
        let content = UNMutableNotificationContent()
        content.title = "\(providerName) — Recovered"
        content.body = "All systems operational"
        content.sound = .default

        let identifier = "recovery-\(providerID)-\(Int(Date().timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        if Bundle.main.bundleIdentifier != nil {
            let center = UNUserNotificationCenter.current()
            try? await center.add(request)
        }
    }

    /// Deterministic identifier for deduplication.
    static func notificationIdentifier(providerID: String, incidentID: String) -> String {
        "\(providerID)-\(incidentID)"
    }
}

import Foundation
import UserNotifications

@Observable
class NotificationManager {
    /// Tracks "providerID-incidentID" → last notified status
    private var notifiedIncidents: [String: IncidentStatus] = [:]

    /// Request notification permission from macOS.
    func requestPermission() async {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Check if we should notify for this incident (new or status changed).
    func shouldNotify(providerID: String, incident: Incident) -> Bool {
        let key = Self.notificationIdentifier(providerID: providerID, incidentID: incident.id)
        guard let previousStatus = notifiedIncidents[key] else {
            return true // never notified
        }
        return previousStatus != incident.status // status changed
    }

    /// Mark an incident as notified with its current status.
    func markNotified(providerID: String, incident: Incident) {
        let key = Self.notificationIdentifier(providerID: providerID, incidentID: incident.id)
        notifiedIncidents[key] = incident.status
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

    /// Deterministic identifier for deduplication.
    static func notificationIdentifier(providerID: String, incidentID: String) -> String {
        "\(providerID)-\(incidentID)"
    }
}

import Testing
import Foundation
@testable import LLMStatus

@Suite("NotificationManager")
struct NotificationManagerTests {

    // MARK: - shouldNotify logic

    @Test("New incident → should notify")
    func newIncident() {
        let manager = NotificationManager()
        let incident = makeIncident(id: "inc-001", status: .investigating)
        #expect(manager.shouldNotify(providerID: "anthropic", incident: incident))
    }

    @Test("Same incident already notified → should NOT notify")
    func alreadyNotified() {
        let manager = NotificationManager()
        let incident = makeIncident(id: "inc-001", status: .investigating)

        manager.markNotified(providerID: "anthropic", incident: incident)
        #expect(!manager.shouldNotify(providerID: "anthropic", incident: incident))
    }

    @Test("Same incident, different status → should notify (escalation)")
    func statusChanged() {
        let manager = NotificationManager()
        let incident1 = makeIncident(id: "inc-001", status: .investigating)
        let incident2 = makeIncident(id: "inc-001", status: .identified)

        manager.markNotified(providerID: "anthropic", incident: incident1)
        #expect(manager.shouldNotify(providerID: "anthropic", incident: incident2))
    }

    @Test("Different provider, same incident ID → should notify")
    func differentProvider() {
        let manager = NotificationManager()
        let incident = makeIncident(id: "inc-001", status: .investigating)

        manager.markNotified(providerID: "anthropic", incident: incident)
        #expect(manager.shouldNotify(providerID: "openai", incident: incident))
    }

    @Test("Notification identifier is deterministic")
    func deterministicIdentifier() {
        let id1 = NotificationManager.notificationIdentifier(providerID: "anthropic", incidentID: "inc-001")
        let id2 = NotificationManager.notificationIdentifier(providerID: "anthropic", incidentID: "inc-001")
        #expect(id1 == id2)
        #expect(id1 == "anthropic-inc-001")
    }

    // MARK: - Helpers

    private func makeIncident(id: String, status: IncidentStatus) -> Incident {
        Incident(
            id: id,
            name: "Test Incident",
            impact: .major,
            status: status,
            createdAt: Date(),
            resolvedAt: nil,
            shortlink: nil,
            updates: [],
            affectedComponents: []
        )
    }
}

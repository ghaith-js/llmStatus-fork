import Testing
import SwiftUI
@testable import LLMStatus

@Suite("ServiceStatus")
struct ServiceStatusTests {

    // MARK: - init(fromIndicator:)

    @Test("'none' maps to .operational")
    func indicatorNone() {
        #expect(ServiceStatus(fromIndicator: "none") == .operational)
    }

    @Test("'minor' maps to .degraded")
    func indicatorMinor() {
        #expect(ServiceStatus(fromIndicator: "minor") == .degraded)
    }

    @Test("'major' maps to .majorOutage")
    func indicatorMajor() {
        #expect(ServiceStatus(fromIndicator: "major") == .majorOutage)
    }

    @Test("'critical' maps to .critical")
    func indicatorCritical() {
        #expect(ServiceStatus(fromIndicator: "critical") == .critical)
    }

    @Test("Unknown indicator maps to .unknown")
    func indicatorUnknown() {
        #expect(ServiceStatus(fromIndicator: "banana") == .unknown)
        #expect(ServiceStatus(fromIndicator: "") == .unknown)
    }

    // MARK: - color

    @Test("Each status has correct color")
    func colors() {
        #expect(ServiceStatus.operational.color == .green)
        #expect(ServiceStatus.degraded.color == .yellow)
        #expect(ServiceStatus.majorOutage.color == .orange)
        #expect(ServiceStatus.critical.color == .red)
        #expect(ServiceStatus.unknown.color == .gray)
    }

    // MARK: - sfSymbol

    @Test("Each status has correct SF Symbol")
    func sfSymbols() {
        #expect(ServiceStatus.operational.sfSymbol == "checkmark.circle.fill")
        #expect(ServiceStatus.degraded.sfSymbol == "exclamationmark.triangle.fill")
        #expect(ServiceStatus.majorOutage.sfSymbol == "xmark.circle.fill")
        #expect(ServiceStatus.critical.sfSymbol == "xmark.octagon.fill")
        #expect(ServiceStatus.unknown.sfSymbol == "questionmark.circle.fill")
    }

    // MARK: - severity ordering

    @Test("Severity ordering: operational < unknown < degraded < majorOutage < critical")
    func severityOrdering() {
        #expect(ServiceStatus.operational.severity < ServiceStatus.unknown.severity)
        #expect(ServiceStatus.unknown.severity < ServiceStatus.degraded.severity)
        #expect(ServiceStatus.degraded.severity < ServiceStatus.majorOutage.severity)
        #expect(ServiceStatus.majorOutage.severity < ServiceStatus.critical.severity)
    }

    // MARK: - label

    @Test("Each status has readable label")
    func labels() {
        #expect(ServiceStatus.operational.label == "Operational")
        #expect(ServiceStatus.degraded.label == "Degraded")
        #expect(ServiceStatus.majorOutage.label == "Major Outage")
        #expect(ServiceStatus.critical.label == "Critical")
        #expect(ServiceStatus.unknown.label == "Unknown")
    }
}

@Suite("Provider gallery card")
struct ProviderImpactedTests {
    private func provider(components: [ServiceComponent] = [], incidents: [Incident] = []) -> ServiceProvider {
        let url = URL(string: "https://example.com")!
        return ServiceProvider(id: "p", name: "Provider", shortName: "P", statusURL: url, apiBaseURL: url,
                               fetcherType: .statuspage, currentStatus: .degraded, incidents: incidents, components: components)
    }

    private func incident(_ name: String, affected: [String], resolved: Bool = false) -> Incident {
        Incident(id: name, name: name, impact: .minor, status: .investigating, createdAt: Date(),
                 resolvedAt: resolved ? Date() : nil, shortlink: nil, updates: [], affectedComponents: affected)
    }

    @Test("Impacted lists degraded leaf components with their own status, once each")
    func components() {
        let group = ServiceComponent(id: "g", name: "APIs", status: .majorOutage, children: [
            ServiceComponent(id: "a", name: "Chat", status: .majorOutage),
            ServiceComponent(id: "b", name: "Files", status: .operational),
            ServiceComponent(id: "c", name: "Login", status: .degraded),
        ])
        let other = ServiceComponent(id: "d", name: "Login", status: .degraded)
        let impacted = provider(components: [group, other]).impacted
        #expect(impacted.map(\.name) == ["Chat", "Login"])
        #expect(impacted.map(\.status) == [.majorOutage, .degraded])
    }

    @Test("Without degraded components, active incidents name what is impacted")
    func incidents() {
        let named = provider(incidents: [incident("Errors", affected: ["API", "Console"]), incident("Old", affected: ["Web"], resolved: true)])
        #expect(named.impacted.map(\.name) == ["API", "Console"])
        #expect(provider(incidents: [incident("Elevated errors", affected: [])]).impacted.map(\.name) == ["Elevated errors"])
        #expect(provider().impacted.isEmpty)
    }
}

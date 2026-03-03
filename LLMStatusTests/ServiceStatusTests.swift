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

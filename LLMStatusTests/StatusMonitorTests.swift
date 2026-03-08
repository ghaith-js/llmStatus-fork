import Testing
import Foundation
@testable import LLMStatus

@Suite("StatusMonitor")
struct StatusMonitorTests {

    // MARK: - Aggregation logic

    @Test("All operational → aggregated is operational")
    func allOperational() {
        let monitor = StatusMonitor()
        monitor.providers = makeProviders([.operational, .operational])
        #expect(monitor.aggregatedStatus == .operational)
    }

    @Test("One degraded among operational → aggregated is degraded")
    func oneDegraded() {
        let monitor = StatusMonitor()
        monitor.providers = makeProviders([.operational, .degraded])
        #expect(monitor.aggregatedStatus == .degraded)
    }

    @Test("One majorOutage → aggregated is majorOutage")
    func oneMajorOutage() {
        let monitor = StatusMonitor()
        monitor.providers = makeProviders([.operational, .majorOutage, .degraded])
        #expect(monitor.aggregatedStatus == .majorOutage)
    }

    @Test("One critical → aggregated is critical regardless of others")
    func oneCritical() {
        let monitor = StatusMonitor()
        monitor.providers = makeProviders([.operational, .degraded, .critical])
        #expect(monitor.aggregatedStatus == .critical)
    }

    @Test("All unknown (fetch failures) → aggregated is unknown")
    func allUnknown() {
        let monitor = StatusMonitor()
        monitor.providers = makeProviders([.unknown, .unknown])
        #expect(monitor.aggregatedStatus == .unknown)
    }

    @Test("Empty providers → aggregated is unknown")
    func emptyProviders() {
        let monitor = StatusMonitor()
        monitor.providers = []
        #expect(monitor.aggregatedStatus == .unknown)
    }

    // MARK: - Default providers

    @Test("Monitor initializes with all default providers")
    func defaultProviders() {
        let monitor = StatusMonitor()
        #expect(monitor.providers.count == 9)
        #expect(monitor.providers.contains { $0.id == "anthropic" })
        #expect(monitor.providers.contains { $0.id == "openai" })
        #expect(monitor.providers.contains { $0.id == "google" })
        #expect(monitor.providers.contains { $0.id == "mistral" })
        #expect(monitor.providers.contains { $0.id == "deepseek" })
        #expect(monitor.providers.contains { $0.id == "moonshot" })
        #expect(monitor.providers.contains { $0.id == "openrouter" })
        #expect(monitor.providers.contains { $0.id == "perplexity" })
    }

    // MARK: - Helpers

    private func makeProviders(_ statuses: [ServiceStatus]) -> [ServiceProvider] {
        statuses.enumerated().map { index, status in
            ServiceProvider(
                id: "provider-\(index)",
                name: "Provider \(index)",
                shortName: "P\(index)",
                statusURL: URL(string: "https://example.com")!,
                apiBaseURL: URL(string: "https://example.com/api/v2")!,
                fetcherType: .statuspage,
                currentStatus: status,
                lastChecked: Date(),
                incidents: []
            )
        }
    }
}

import Foundation
import Testing
@testable import LLMStatus

@Suite("OpenRouter Datadog status")
struct OpenRouterFetcherTests {
    private func component(_ status: String = "operational") -> String {
        #"{"id":"chat","name":"Chat","type":"Component","status":"\#(status)"}"#
    }

    private func parse(_ components: String, incidents: String = "[]", maintenances: String = "null") -> OpenRouterFetcher.Snapshot {
        OpenRouterFetcher.parse(Data(#"{"components":[\#(components)],"incidents":\#(incidents),"maintenances":\#(maintenances)}"#.utf8))
    }

    @Test("Current healthy groups ignore degraded resolved incident history")
    func resolvedHistory() {
        let group = #"{"id":"gateway","name":"API - Gateway","type":"ComponentGroup","components":[\#(component())]}"#
        let history = #"[{"resolved":true,"currentStatus":"resolved","componentsAffected":[\#(component("degraded"))],"timeline":[{"status":"investigating","description":"major outage"}]}]"#
        let result = parse(group, incidents: history)
        #expect(result.status == .operational)
        #expect(result.components.first?.isGroup == true)
        #expect(result.components.first?.children.first?.status == .operational)
    }

    @Test("Component severity follows the existing status model", arguments: [
        ("operational", ServiceStatus.operational), ("degraded", .degraded),
        ("maintenance", .degraded), ("partial_outage", .majorOutage),
        ("major_outage", .critical), ("unexpected", .unknown)
    ])
    func componentSeverity(value: (String, ServiceStatus)) {
        let group = #"{"id":"gateway","name":"Gateway","type":"ComponentGroup","components":[\#(component(value.0))]}"#
        #expect(parse(group).status == value.1)
        #expect(parse(group).components.first?.status == value.1)
    }

    @Test("An active incident is detected even if components are operational")
    func activeIncident() {
        let active = #"[{"resolved":false,"currentStatus":"investigating","componentsAffected":[\#(component("major_outage"))]}]"#
        #expect(parse(component(), incidents: active).status == .critical)
        let advisory = #"[{"resolved":false,"currentStatus":"monitoring","componentsAffected":[]}]"#
        #expect(parse(component(), incidents: advisory).status == .degraded)
    }

    @Test("Only maintenance in progress affects status", arguments: ["scheduled", "in_progress", "completed", "canceled"])
    func maintenance(state: String) {
        let notices = #"[{"currentStatus":"\#(state)"}]"#
        #expect(parse(component(), maintenances: notices).status == (state == "in_progress" ? .degraded : .operational))
    }

    @Test("Missing or unreadable data is unknown, never a fabricated outage", arguments: [
        "<html><script src='app.js'></script></html>", "{}", "{\"components\":[]}",
        "{\"components\":[{\"id\":\"empty\",\"name\":\"Empty\",\"type\":\"ComponentGroup\"}]}",
        "{\"components\":[{\"id\":\"chat\",\"name\":\"Chat\",\"type\":\"Component\"}]}"
    ])
    func unreadable(body: String) {
        #expect(OpenRouterFetcher.parse(Data(body.utf8)).status == .unknown)
    }

    @Test("OpenRouter is routed to its JSON fetcher")
    func routing() {
        #expect(StatusMonitor().providers.first { $0.id == "openrouter" }?.fetcherType == .openrouter)
    }
}

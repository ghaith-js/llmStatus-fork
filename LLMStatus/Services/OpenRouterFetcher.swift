import Foundation

/// OpenRouter's Datadog page is a JavaScript shell; config.json holds its live data.
enum OpenRouterFetcher {
    struct Snapshot {
        let status: ServiceStatus
        let components: [ServiceComponent]
    }

    private struct Page: Decodable {
        let components: [Component]
        let incidents: [Notice]?
        let maintenances: [Notice]?
    }

    private struct Component: Decodable {
        let id: String
        let name: String
        let type: String
        let status: String?
        let components: [Component]?

        var serviceComponent: ServiceComponent {
            let children = type == "ComponentGroup" ? (components ?? []).map(\.serviceComponent) : []
            return ServiceComponent(
                id: id, name: name,
                status: type == "ComponentGroup"
                    ? OpenRouterFetcher.worst(children.map(\.status))
                    : OpenRouterFetcher.status(from: status),
                children: children
            )
        }
    }

    private struct Notice: Decodable {
        let resolved: Bool?
        let currentStatus: String
        let componentsAffected: [Component]?
    }

    static func fetch(baseURL: URL) async -> Snapshot {
        guard let data = await HTTPClient.fetch(
            baseURL.appendingPathComponent("config.json"), source: "OpenRouterFetcher"
        ) else { return Snapshot(status: .unknown, components: []) }
        return parse(data)
    }

    static func parse(_ data: Data) -> Snapshot {
        guard let page = try? JSONDecoder().decode(Page.self, from: data) else {
            return Snapshot(status: .unknown, components: [])
        }
        let components = page.components.map(\.serviceComponent)
        var statuses = components.map(\.status)
        // Only current incident state counts; resolved incidents and their timelines are history.
        for incident in page.incidents ?? [] where incident.resolved != true && incident.currentStatus != "resolved" {
            statuses.append(worst((incident.componentsAffected ?? []).map { $0.serviceComponent.status }))
            statuses.append(.degraded)
        }
        if (page.maintenances ?? []).contains(where: { $0.currentStatus == "in_progress" }) {
            statuses.append(.degraded)
        }
        return Snapshot(status: worst(statuses), components: components)
    }

    private static func status(from value: String?) -> ServiceStatus {
        switch value {
        case "operational": .operational
        case "degraded", "maintenance": .degraded
        case "partial_outage": .majorOutage
        case "major_outage": .critical
        default: .unknown
        }
    }

    private static func worst(_ statuses: [ServiceStatus]) -> ServiceStatus {
        statuses.max(by: { $0.severity < $1.severity }) ?? .unknown
    }
}

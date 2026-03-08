import Foundation

/// Fetcher for Atlassian Statuspage API (Anthropic, OpenAI, DeepSeek, Moonshot).
enum StatusFetcher {
    static func fetchStatus(baseURL: URL) async -> StatusResponse? {
        guard let data = await HTTPClient.fetch(
            baseURL.appendingPathComponent("status.json"), source: "StatusFetcher"
        ) else { return nil }
        return try? JSONDecoder().decode(StatusResponse.self, from: data)
    }

    static func fetchComponents(baseURL: URL) async -> [ServiceComponent] {
        guard let data = await HTTPClient.fetch(
            baseURL.appendingPathComponent("components.json"), source: "StatusFetcher"
        ) else { return [] }
        guard let decoded = try? JSONDecoder().decode(ComponentsResponse.self, from: data) else { return [] }

        let allDTOs = decoded.components
        let groups = allDTOs.filter { $0.group == true }
        let children = allDTOs.filter { $0.group != true }

        // If no groups, return flat list
        guard !groups.isEmpty else {
            return children.map { $0.toServiceComponent() }
        }

        // Build grouped hierarchy
        let childrenByGroup = Dictionary(grouping: children, by: { $0.groupId ?? "" })
        return groups.map { group in
            let groupChildren = (childrenByGroup[group.id] ?? []).map { $0.toServiceComponent() }
            return ServiceComponent(
                id: group.id,
                name: group.name,
                status: ServiceStatus(fromComponentStatus: group.status),
                children: groupChildren
            )
        }
    }

    static func fetchIncidents(baseURL: URL) async -> [Incident] {
        guard let data = await HTTPClient.fetch(
            baseURL.appendingPathComponent("incidents/unresolved.json"), source: "StatusFetcher"
        ) else { return [] }
        guard let decoded = try? JSONDecoder().decode(IncidentsResponse.self, from: data) else { return [] }
        return decoded.incidents.compactMap { $0.toIncident() }
    }
}

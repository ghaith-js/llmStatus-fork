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
        return decoded.components
            .filter { $0.group != true }
            .map { $0.toServiceComponent() }
    }

    static func fetchIncidents(baseURL: URL) async -> [Incident] {
        guard let data = await HTTPClient.fetch(
            baseURL.appendingPathComponent("incidents/unresolved.json"), source: "StatusFetcher"
        ) else { return [] }
        guard let decoded = try? JSONDecoder().decode(IncidentsResponse.self, from: data) else { return [] }
        return decoded.incidents.compactMap { $0.toIncident() }
    }
}

import Foundation

/// Fetches status from Groq's incident.io API (groqstatus.com/api/v1/summary).
enum GroqFetcher {
    struct SummaryResponse: Codable {
        let ongoingIncidents: [GroqIncident]
        let inProgressMaintenances: [GroqIncident]

        enum CodingKeys: String, CodingKey {
            case ongoingIncidents = "ongoing_incidents"
            case inProgressMaintenances = "in_progress_maintenances"
        }
    }

    struct GroqIncident: Codable {
        let id: String
        let name: String
        let status: String
        let url: String?
        let affectedComponents: [GroqComponent]?
        let lastUpdateAt: String?
        let lastUpdateMessage: String?

        enum CodingKeys: String, CodingKey {
            case id, name, status, url
            case affectedComponents = "affected_components"
            case lastUpdateAt = "last_update_at"
            case lastUpdateMessage = "last_update_message"
        }
    }

    struct GroqComponent: Codable {
        let id: String
        let name: String
        let currentStatus: String?

        enum CodingKeys: String, CodingKey {
            case id, name
            case currentStatus = "current_status"
        }
    }

    static func fetchStatus(baseURL: URL) async -> ServiceStatus {
        guard let data = await HTTPClient.fetch(
            baseURL.appendingPathComponent("api/v1/summary"), source: "GroqFetcher"
        ) else { return .unknown }

        guard let summary = try? JSONDecoder().decode(SummaryResponse.self, from: data) else { return .unknown }

        if summary.ongoingIncidents.isEmpty && summary.inProgressMaintenances.isEmpty {
            return .operational
        }

        let statuses = summary.ongoingIncidents
            .flatMap { $0.affectedComponents ?? [] }
            .compactMap { $0.currentStatus }

        if statuses.contains("full_outage") { return .critical }
        if statuses.contains("partial_outage") { return .majorOutage }
        if statuses.contains("degraded_performance") { return .degraded }

        return summary.ongoingIncidents.isEmpty ? .operational : .degraded
    }

    static func fetchIncidents(baseURL: URL) async -> [Incident] {
        guard let data = await HTTPClient.fetch(
            baseURL.appendingPathComponent("api/v1/summary"), source: "GroqFetcher"
        ) else { return [] }

        guard let summary = try? JSONDecoder().decode(SummaryResponse.self, from: data) else { return [] }
        return summary.ongoingIncidents.map { inc in
            Incident(
                id: inc.id,
                name: inc.name,
                impact: .major,
                status: .investigating,
                createdAt: ISO8601DateFormatter().date(from: inc.lastUpdateAt ?? "") ?? Date(),
                resolvedAt: nil,
                shortlink: inc.url,
                updates: [],
                affectedComponents: inc.affectedComponents?.map(\.name) ?? []
            )
        }
    }
}

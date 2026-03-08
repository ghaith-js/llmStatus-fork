import Foundation

private let log = FileLogger.shared

/// Fetches status from Groq's incident.io API (groqstatus.com/api/v1/summary).
enum GroqFetcher {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

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
        let url = baseURL.appendingPathComponent("api/v1/summary")
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                log.warning("Non-200 for \(url)", source: "GroqFetcher")
                return .unknown
            }
            let summary = try JSONDecoder().decode(SummaryResponse.self, from: data)

            if summary.ongoingIncidents.isEmpty && summary.inProgressMaintenances.isEmpty {
                return .operational
            }

            // Check severity from component statuses
            let statuses = summary.ongoingIncidents
                .flatMap { $0.affectedComponents ?? [] }
                .compactMap { $0.currentStatus }

            if statuses.contains("full_outage") { return .critical }
            if statuses.contains("partial_outage") { return .majorOutage }
            if statuses.contains("degraded_performance") { return .degraded }

            return summary.ongoingIncidents.isEmpty ? .operational : .degraded
        } catch {
            log.error("fetchStatus failed: \(error.localizedDescription)", source: "GroqFetcher")
            return .unknown
        }
    }

    static func fetchIncidents(baseURL: URL) async -> [Incident] {
        let url = baseURL.appendingPathComponent("api/v1/summary")
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            let summary = try JSONDecoder().decode(SummaryResponse.self, from: data)
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
        } catch {
            log.error("fetchIncidents failed: \(error.localizedDescription)", source: "GroqFetcher")
            return []
        }
    }
}

import Foundation

private let log = FileLogger.shared

/// Fetches Gemini status from Google Cloud's incidents.json, filtered by Vertex Gemini API product.
enum GoogleFetcher {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    /// Product IDs related to Vertex AI / Gemini on Google Cloud.
    private static let geminiProductIDs: Set<String> = [
        "Z0FZJAMvEB4j3NbCJs6B", // Vertex Gemini API
        "sdXM79fz1FS6ekNpu37K", // Vertex AI Online Prediction
        "vNncXxtSVvqyhvSkQ6PJ", // Vertex AI Search
        "zeBmbgdSyHGTvPAiXwVS", // Vertex Imagen API
    ]

    struct GoogleIncident: Codable {
        let id: String
        let externalDesc: String
        let statusImpact: String
        let severity: String
        let affectedProducts: [AffectedProduct]
        let mostRecentUpdate: MostRecentUpdate?
        let currentlyAffectedLocations: [AffectedLocation]?
        let begin: String?
        let end: String?
        let uri: String?

        enum CodingKeys: String, CodingKey {
            case id
            case externalDesc = "external_desc"
            case statusImpact = "status_impact"
            case severity
            case affectedProducts = "affected_products"
            case mostRecentUpdate = "most_recent_update"
            case currentlyAffectedLocations = "currently_affected_locations"
            case begin, end, uri
        }
    }

    struct AffectedProduct: Codable {
        let title: String
        let id: String
    }

    struct MostRecentUpdate: Codable {
        let status: String?
    }

    struct AffectedLocation: Codable {
        let title: String?
        let id: String?
    }

    static func fetchStatus(baseURL: URL) async -> ServiceStatus {
        let url = baseURL.appendingPathComponent("incidents.json")
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                log.warning("Non-200 for \(url)", source: "GoogleFetcher")
                return .unknown
            }
            let incidents = try JSONDecoder().decode([GoogleIncident].self, from: data)
            let active = activeGeminiIncidents(incidents)

            if active.isEmpty { return .operational }
            if active.contains(where: { $0.severity == "high" }) { return .critical }
            if active.contains(where: { $0.statusImpact == "SERVICE_DISRUPTION" }) { return .majorOutage }
            return .degraded
        } catch {
            log.error("fetchStatus failed: \(error.localizedDescription)", source: "GoogleFetcher")
            return .unknown
        }
    }

    static func fetchIncidents(baseURL: URL) async -> [Incident] {
        let url = baseURL.appendingPathComponent("incidents.json")
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            let incidents = try JSONDecoder().decode([GoogleIncident].self, from: data)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]

            return activeGeminiIncidents(incidents).map { inc in
                let impact: IncidentImpact = switch inc.severity {
                    case "high": .critical
                    case "medium": .major
                    default: .minor
                }
                return Incident(
                    id: inc.id,
                    name: inc.externalDesc,
                    impact: impact,
                    status: .investigating,
                    createdAt: formatter.date(from: inc.begin ?? "") ?? Date(),
                    resolvedAt: nil,
                    shortlink: inc.uri.map { "https://status.cloud.google.com/\($0)" },
                    updates: [],
                    affectedComponents: inc.affectedProducts.map(\.title)
                )
            }
        } catch {
            log.error("fetchIncidents failed: \(error.localizedDescription)", source: "GoogleFetcher")
            return []
        }
    }

    /// Filter for active Gemini-related incidents (non-empty affected locations).
    private static func activeGeminiIncidents(_ incidents: [GoogleIncident]) -> [GoogleIncident] {
        incidents.filter { inc in
            let isGemini = inc.affectedProducts.contains { geminiProductIDs.contains($0.id) }
            let isActive = !(inc.currentlyAffectedLocations ?? []).isEmpty
            return isGemini && isActive
        }
    }
}

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.llmstatus", category: "StatusFetcher")

enum StatusFetcher {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    /// Fetch overall status from /api/v2/status.json
    static func fetchStatus(baseURL: URL) async -> StatusResponse? {
        let url = baseURL.appendingPathComponent("status.json")
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                logger.warning("Non-200 status for \(url)")
                return nil
            }
            return try JSONDecoder().decode(StatusResponse.self, from: data)
        } catch {
            logger.error("fetchStatus failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Fetch unresolved incidents from /api/v2/incidents/unresolved.json
    static func fetchIncidents(baseURL: URL) async -> [Incident] {
        let url = baseURL.appendingPathComponent("incidents/unresolved.json")
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                logger.warning("Non-200 status for \(url)")
                return []
            }
            let decoded = try JSONDecoder().decode(IncidentsResponse.self, from: data)
            return decoded.incidents.compactMap { $0.toIncident() }
        } catch {
            logger.error("fetchIncidents failed: \(error.localizedDescription)")
            return []
        }
    }
}

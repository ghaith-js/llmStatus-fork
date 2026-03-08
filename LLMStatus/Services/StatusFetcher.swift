import Foundation

private let log = FileLogger.shared

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
                log.warning("Non-200 status for \(url)", source: "StatusFetcher")
                return nil
            }
            return try JSONDecoder().decode(StatusResponse.self, from: data)
        } catch {
            log.error("fetchStatus failed: \(error.localizedDescription)", source: "StatusFetcher")
            return nil
        }
    }

    /// Fetch components from /api/v2/components.json
    static func fetchComponents(baseURL: URL) async -> [ServiceComponent] {
        let url = baseURL.appendingPathComponent("components.json")
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                log.warning("Non-200 status for \(url)", source: "StatusFetcher")
                return []
            }
            let decoded = try JSONDecoder().decode(ComponentsResponse.self, from: data)
            // Filter out group headers (group=true) — keep only actual components
            return decoded.components
                .filter { $0.group != true }
                .map { $0.toServiceComponent() }
        } catch {
            log.error("fetchComponents failed: \(error.localizedDescription)", source: "StatusFetcher")
            return []
        }
    }

    /// Fetch unresolved incidents from /api/v2/incidents/unresolved.json
    static func fetchIncidents(baseURL: URL) async -> [Incident] {
        let url = baseURL.appendingPathComponent("incidents/unresolved.json")
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                log.warning("Non-200 status for \(url)", source: "StatusFetcher")
                return []
            }
            let decoded = try JSONDecoder().decode(IncidentsResponse.self, from: data)
            return decoded.incidents.compactMap { $0.toIncident() }
        } catch {
            log.error("fetchIncidents failed: \(error.localizedDescription)", source: "StatusFetcher")
            return []
        }
    }
}

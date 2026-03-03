import Foundation

enum StatusFetcher {

    /// Fetch overall status from /api/v2/status.json
    static func fetchStatus(baseURL: URL) async -> StatusResponse? {
        let url = baseURL.appendingPathComponent("status.json")
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            return try decoder.decode(StatusResponse.self, from: data)
        } catch {
            return nil
        }
    }

    /// Fetch unresolved incidents from /api/v2/incidents/unresolved.json
    static func fetchIncidents(baseURL: URL) async -> [Incident] {
        let url = baseURL.appendingPathComponent("incidents/unresolved.json")
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            let response = try decoder.decode(IncidentsResponse.self, from: data)
            return response.incidents.compactMap { $0.toIncident() }
        } catch {
            return []
        }
    }
}

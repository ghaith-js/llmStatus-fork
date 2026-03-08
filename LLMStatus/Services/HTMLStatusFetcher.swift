import Foundation

private let log = FileLogger.shared

/// Generic fetcher for status pages without a JSON API.
/// Determines status by searching for keywords in the rendered HTML.
enum HTMLStatusFetcher {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    static func fetchStatus(baseURL: URL) async -> ServiceStatus {
        guard let html = await fetchHTML(baseURL: baseURL) else { return .unknown }

        let lower = html.lowercased()

        // Check for operational (case-insensitive)
        if lower.contains("all systems operational") {
            return .operational
        }

        // Check for severity keywords
        if lower.contains("major outage") || lower.contains("major_outage") || lower.contains("full_outage") {
            return .majorOutage
        }
        if lower.contains("degraded") || lower.contains("partial outage") || lower.contains("partial_outage") {
            return .degraded
        }

        // Page loaded but no clear operational signal
        return .degraded
    }

    static func fetchIncidents(baseURL: URL) async -> [Incident] {
        // HTML-based pages don't expose structured incident data reliably
        return []
    }

    private static func fetchHTML(baseURL: URL) async -> String? {
        do {
            let (data, response) = try await session.data(from: baseURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                log.warning("Non-200 for \(baseURL)", source: "HTMLStatusFetcher")
                return nil
            }
            return String(data: data, encoding: .utf8)
        } catch {
            log.error("fetchHTML failed: \(error.localizedDescription)", source: "HTMLStatusFetcher")
            return nil
        }
    }
}

import Foundation

/// Shared HTTP client for all fetchers.
enum HTTPClient {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    /// Fetch data from URL, returning nil on non-2xx or network error.
    static func fetch(_ url: URL, source: String) async -> Data? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                FileLogger.shared.warning("Non-200 for \(url)", source: source)
                return nil
            }
            return data
        } catch {
            FileLogger.shared.error("Fetch failed: \(error.localizedDescription)", source: source)
            return nil
        }
    }
}

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
        return []
    }

    /// Parse components from OnlineOrNot-style HTML status pages.
    /// Pattern: <p class="...text-white">NAME</p> ... <span class="capitalize ...">STATUS</span>
    static func fetchComponents(baseURL: URL) async -> [ServiceComponent] {
        guard let html = await fetchHTML(baseURL: baseURL) else { return [] }

        // Match: component name in <p> tag followed by status in <span> with "capitalize" class
        // OnlineOrNot pattern: <p class="text-gray-900 dark:text-white">NAME</p> ... <span class="capitalize ...">STATUS</span>
        var components: [ServiceComponent] = []
        let pattern = #"<p class="text-gray-900 dark:text-white">([^<]+)</p>.*?<span class="capitalize[^"]*">(\w+)</span>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return []
        }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        for match in matches {
            guard match.numberOfRanges == 3 else { continue }
            let name = nsHTML.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let statusStr = nsHTML.substring(with: match.range(at: 2)).lowercased()

            let status: ServiceStatus = switch statusStr {
            case "operational": .operational
            case "degraded": .degraded
            case "outage": .majorOutage
            default: .unknown
            }

            components.append(ServiceComponent(id: name, name: name, status: status))
        }

        return components
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

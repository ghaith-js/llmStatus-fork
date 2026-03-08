import Foundation

/// Generic fetcher for status pages without a JSON API.
/// Determines status by searching for keywords in the rendered HTML.
enum HTMLStatusFetcher {
    static func fetchStatus(baseURL: URL) async -> ServiceStatus {
        guard let html = await fetchHTML(baseURL: baseURL) else { return .unknown }

        let lower = html.lowercased()

        if lower.contains("all systems operational") {
            return .operational
        }
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
    static func fetchComponents(baseURL: URL) async -> [ServiceComponent] {
        guard let html = await fetchHTML(baseURL: baseURL) else { return [] }

        let pattern = #"<p class="text-gray-900 dark:text-white">([^<]+)</p>.*?<span class="capitalize[^"]*">(\w+)</span>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return []
        }

        var components: [ServiceComponent] = []
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
        guard let data = await HTTPClient.fetch(baseURL, source: "HTMLStatusFetcher") else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

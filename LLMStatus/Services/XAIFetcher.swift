import Foundation
import WebKit

private let log = FileLogger.shared

/// Fetches xAI status using a hidden WKWebView to bypass Cloudflare.
/// Results are cached for 10 minutes.
enum XAIFetcher {
    private static let cacheDuration: TimeInterval = 600
    private static var cachedStatus: ServiceStatus?
    private static var cachedIncidents: [Incident] = []
    private static var lastFetchDate: Date?
    private static var isFetching = false
    static var progressMessage: String?

    static var hasCachedResult: Bool {
        guard let lastFetch = lastFetchDate else { return false }
        return Date().timeIntervalSince(lastFetch) < cacheDuration
    }

    static func invalidateCache() {
        lastFetchDate = nil
    }

    static func fetchStatus(baseURL: URL) async -> ServiceStatus {
        await refreshCacheIfNeeded()
        return cachedStatus ?? .unknown
    }

    static func fetchIncidents(baseURL: URL) async -> [Incident] {
        await refreshCacheIfNeeded()
        return cachedIncidents
    }

    private static func refreshCacheIfNeeded() async {
        if let lastFetch = lastFetchDate, Date().timeIntervalSince(lastFetch) < cacheDuration {
            return
        }
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        progressMessage = "Loading status page..."

        // WKWebView must run on main thread
        let html = await loadPageWithWebKit(url: URL(string: "https://status.x.ai/")!)

        guard let html, !html.isEmpty else {
            log.warning("WebKit returned no HTML", source: "XAIFetcher")
            cachedStatus = .unknown
            cachedIncidents = []
            lastFetchDate = Date()
            progressMessage = nil
            return
        }

        let (status, incidents) = parseHTML(html)
        cachedStatus = status
        cachedIncidents = incidents
        lastFetchDate = Date()
        progressMessage = nil
    }

    // MARK: - WebKit loader

    @MainActor
    private static func loadPageWithWebKit(url: URL) async -> String? {
        await withCheckedContinuation { continuation in
            let config = WKWebViewConfiguration()
            let webView = WKWebView(frame: .zero, configuration: config)

            let delegate = WebViewDelegate { html in
                continuation.resume(returning: html)
            }
            webView.navigationDelegate = delegate

            // Prevent delegate from being deallocated
            objc_setAssociatedObject(webView, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)

            webView.load(URLRequest(url: url))

            // Timeout after 30s
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                if !delegate.didFinish {
                    log.warning("WebKit timeout after 30s", source: "XAIFetcher")
                    delegate.didFinish = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - HTML parsing

    private static func parseHTML(_ html: String) -> (ServiceStatus, [Incident]) {
        let lower = html.lowercased()

        let status: ServiceStatus
        if lower.contains("no incidents declared") || lower.contains("no known incidents") {
            status = .operational
        } else if lower.contains("major outage") || lower.contains("major_outage") {
            status = .critical
        } else if lower.contains("degraded") || lower.contains("partial outage") {
            status = .degraded
        } else if lower.contains("incidents declared") {
            status = .degraded
        } else {
            status = .unknown
        }

        var incidents: [Incident] = []
        if status != .operational {
            let pattern = #"heading-3["\s>]+([^<]+)"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
                for match in matches {
                    if let range = Range(match.range(at: 1), in: html) {
                        let name = String(html[range]).trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty, !name.contains("No incidents") else { continue }
                        incidents.append(Incident(
                            id: String(name.prefix(32)),
                            name: name,
                            impact: .major,
                            status: .investigating,
                            createdAt: Date(),
                            resolvedAt: nil,
                            shortlink: "https://status.x.ai",
                            updates: [],
                            affectedComponents: []
                        ))
                    }
                }
            }
        }

        return (status, incidents)
    }
}

// MARK: - WKNavigationDelegate

private class WebViewDelegate: NSObject, WKNavigationDelegate {
    let completion: (String?) -> Void
    var didFinish = false

    init(completion: @escaping (String?) -> Void) {
        self.completion = completion
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Wait for Cloudflare JS challenge to resolve
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, !self.didFinish else { return }
            webView.evaluateJavaScript("document.documentElement.outerHTML") { result, error in
                guard !self.didFinish else { return }
                self.didFinish = true
                if let html = result as? String {
                    self.completion(html)
                } else {
                    FileLogger.shared.error("JS eval failed: \(error?.localizedDescription ?? "unknown")", source: "XAIFetcher")
                    self.completion(nil)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !didFinish else { return }
        didFinish = true
        FileLogger.shared.error("WebKit navigation failed: \(error.localizedDescription)", source: "XAIFetcher")
        completion(nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !didFinish else { return }
        didFinish = true
        FileLogger.shared.error("WebKit provisional failed: \(error.localizedDescription)", source: "XAIFetcher")
        completion(nil)
    }
}

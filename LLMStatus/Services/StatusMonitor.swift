import Foundation

@Observable
class StatusMonitor {
    var providers: [ServiceProvider]
    let notificationManager = NotificationManager()
    var notificationsEnabled = true
    var notifyProviderID = "all"
    var isRefreshing = false
    private var pollingTask: Task<Void, Never>?

    /// Worst status across all providers (highest severity wins).
    var aggregatedStatus: ServiceStatus {
        guard !providers.isEmpty else { return .unknown }
        return providers
            .map(\.currentStatus)
            .max(by: { $0.severity < $1.severity }) ?? .unknown
    }

    /// Status for the menu bar icon — either a specific provider or aggregated.
    func menuBarStatus(for providerID: String) -> ServiceStatus {
        if providerID == "all" {
            return aggregatedStatus
        }
        return providers.first { $0.id == providerID }?.currentStatus ?? .unknown
    }

    /// Short label for the menu bar — provider short name or "LLM".
    func menuBarLabel(for providerID: String) -> String {
        if providerID == "all" {
            return "LLM"
        }
        return providers.first { $0.id == providerID }?.shortName ?? "LLM"
    }

    init() {
        self.providers = Self.defaultProviders()
    }

    // MARK: - Polling

    func startPolling(interval: TimeInterval = 300) {
        stopPolling()
        pollingTask = Task {
            // Fetch immediately on start
            await fetchAllStatuses()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await fetchAllStatuses()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Manual refresh — invalidates caches and resets all providers to loading state
    func forceRefresh() async {
        isRefreshing = true
        XAIFetcher.invalidateCache()
        for index in providers.indices {
            providers[index].currentStatus = .unknown
            providers[index].statusDetail = "Refreshing..."
        }
        await fetchAllStatuses()
        isRefreshing = false
    }

    func fetchAllStatuses() async {
        // Show progress for slow fetchers (xAI uses a headless browser)
        for (index, provider) in providers.enumerated() {
            if provider.fetcherType == .xai && !XAIFetcher.hasCachedResult {
                providers[index].statusDetail = "Launching browser..."
            }
        }

        await withTaskGroup(of: (Int, ServiceStatus, [Incident]).self) { group in
            for (index, provider) in providers.enumerated() {
                let fetcherType = provider.fetcherType
                let baseURL = provider.apiBaseURL
                group.addTask {
                    let status: ServiceStatus
                    let incidents: [Incident]

                    switch fetcherType {
                    case .statuspage:
                        async let s = StatusFetcher.fetchStatus(baseURL: baseURL)
                        async let i = StatusFetcher.fetchIncidents(baseURL: baseURL)
                        let response = await s
                        status = response.map { ServiceStatus(fromIndicator: $0.status.indicator) } ?? .unknown
                        incidents = await i
                    case .groq:
                        async let s = GroqFetcher.fetchStatus(baseURL: baseURL)
                        async let i = GroqFetcher.fetchIncidents(baseURL: baseURL)
                        status = await s
                        incidents = await i
                    case .google:
                        async let s = GoogleFetcher.fetchStatus(baseURL: baseURL)
                        async let i = GoogleFetcher.fetchIncidents(baseURL: baseURL)
                        status = await s
                        incidents = await i
                    case .htmlStatus:
                        async let s = HTMLStatusFetcher.fetchStatus(baseURL: baseURL)
                        async let i = HTMLStatusFetcher.fetchIncidents(baseURL: baseURL)
                        status = await s
                        incidents = await i
                    case .xai:
                        async let s = XAIFetcher.fetchStatus(baseURL: baseURL)
                        async let i = XAIFetcher.fetchIncidents(baseURL: baseURL)
                        status = await s
                        incidents = await i
                    }

                    return (index, status, incidents)
                }
            }

            for await (index, status, incidents) in group {
                providers[index].currentStatus = status
                providers[index].incidents = incidents
                providers[index].lastChecked = Date()
                providers[index].statusDetail = nil

                // Notify only for the prioritized provider (or all)
                guard notificationsEnabled else { continue }
                let providerID = providers[index].id
                guard notifyProviderID == "all" || notifyProviderID == providerID else { continue }
                for incident in incidents where incident.isActive {
                    await notificationManager.sendIncidentNotification(
                        providerName: providers[index].name,
                        providerID: providerID,
                        incident: incident
                    )
                }
            }
        }
    }

    // MARK: - Default Providers

    private static func defaultProviders() -> [ServiceProvider] {
        [
            ServiceProvider(
                id: "anthropic",
                name: "Anthropic (Claude)",
                shortName: "Claude",
                statusURL: URL(string: "https://status.anthropic.com")!,
                apiBaseURL: URL(string: "https://status.anthropic.com/api/v2")!,
                fetcherType: .statuspage,
                currentStatus: .unknown,
                lastChecked: nil,
                incidents: []
            ),
            ServiceProvider(
                id: "openai",
                name: "OpenAI",
                shortName: "OpenAI",
                statusURL: URL(string: "https://status.openai.com")!,
                apiBaseURL: URL(string: "https://status.openai.com/api/v2")!,
                fetcherType: .statuspage,
                currentStatus: .unknown,
                lastChecked: nil,
                incidents: []
            ),
            ServiceProvider(
                id: "google",
                name: "Google (Gemini)",
                shortName: "Gemini",
                statusURL: URL(string: "https://status.cloud.google.com")!,
                apiBaseURL: URL(string: "https://status.cloud.google.com")!,
                fetcherType: .google,
                currentStatus: .unknown,
                lastChecked: nil,
                incidents: []
            ),
            ServiceProvider(
                id: "mistral",
                name: "Mistral AI",
                shortName: "Mistral",
                statusURL: URL(string: "https://status.mistral.ai")!,
                apiBaseURL: URL(string: "https://status.mistral.ai")!,
                fetcherType: .htmlStatus,
                currentStatus: .unknown,
                lastChecked: nil,
                incidents: []
            ),
            ServiceProvider(
                id: "deepseek",
                name: "DeepSeek",
                shortName: "DeepSeek",
                statusURL: URL(string: "https://status.deepseek.com")!,
                apiBaseURL: URL(string: "https://status.deepseek.com/api/v2")!,
                fetcherType: .statuspage,
                currentStatus: .unknown,
                lastChecked: nil,
                incidents: []
            ),
            ServiceProvider(
                id: "moonshot",
                name: "Moonshot AI",
                shortName: "Moonshot",
                statusURL: URL(string: "https://status.moonshot.cn")!,
                apiBaseURL: URL(string: "https://status.moonshot.cn/api/v2")!,
                fetcherType: .statuspage,
                currentStatus: .unknown,
                lastChecked: nil,
                incidents: []
            ),
            ServiceProvider(
                id: "openrouter",
                name: "OpenRouter",
                shortName: "OpenRouter",
                statusURL: URL(string: "https://status.openrouter.ai")!,
                apiBaseURL: URL(string: "https://status.openrouter.ai")!,
                fetcherType: .htmlStatus,
                currentStatus: .unknown,
                lastChecked: nil,
                incidents: []
            ),
            ServiceProvider(
                id: "perplexity",
                name: "Perplexity",
                shortName: "Perplexity",
                statusURL: URL(string: "https://status.perplexity.ai")!,
                apiBaseURL: URL(string: "https://status.perplexity.ai")!,
                fetcherType: .htmlStatus,
                currentStatus: .unknown,
                lastChecked: nil,
                incidents: []
            ),
            ServiceProvider(
                id: "xai",
                name: "xAI (Grok)",
                shortName: "Grok",
                statusURL: URL(string: "https://status.x.ai")!,
                apiBaseURL: URL(string: "https://status.x.ai")!,
                fetcherType: .xai,
                currentStatus: .unknown,
                lastChecked: nil,
                incidents: []
            ),
        ]
    }
}

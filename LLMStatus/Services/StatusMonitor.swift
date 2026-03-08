import Foundation

@Observable
class StatusMonitor {
    var providers: [ServiceProvider]
    let notificationManager = NotificationManager()
    var notificationsEnabled = true
    var notifyProviderID = "all"
    /// True during manual force-refresh (disables Refresh button, shows "Refreshing...")
    var isRefreshing = false
    /// True during any fetch cycle (auto or manual) — shows spinner in footer
    var isPolling = false
    private var pollingTask: Task<Void, Never>?

    /// Timestamp of the last completed fetch cycle
    var lastFullCheck: Date?

    /// IDs of disabled providers — synced from AppSettings
    var disabledProviderIDs: Set<String> = []

    /// Custom display order (provider IDs). Empty = default order.
    var providerOrderIDs: [String] = []

    /// Only enabled providers, respecting custom order with issues bumped to top.
    var enabledProviders: [ServiceProvider] {
        let enabled = providers.filter { !disabledProviderIDs.contains($0.id) }

        // Apply custom order if set
        let ordered: [ServiceProvider]
        if providerOrderIDs.isEmpty {
            ordered = enabled
        } else {
            let lookup = Dictionary(uniqueKeysWithValues: enabled.map { ($0.id, $0) })
            let fromOrder = providerOrderIDs.compactMap { lookup[$0] }
            let remaining = enabled.filter { p in !providerOrderIDs.contains(p.id) }
            ordered = fromOrder + remaining
        }

        // Stable partition: issues first, then the rest in custom order
        let withIssues = ordered.filter { $0.currentStatus.severity >= 2 }
        let rest = ordered.filter { $0.currentStatus.severity < 2 }
        return withIssues + rest
    }

    /// Worst status across enabled providers (highest severity wins).
    var aggregatedStatus: ServiceStatus {
        let active = enabledProviders
        guard !active.isEmpty else { return .unknown }
        return active
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

    /// Reorder the providers array to match the given ID order.
    func reorderProviders(orderedIDs: [String]) {
        providerOrderIDs = orderedIDs
        let lookup = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        let reordered = orderedIDs.compactMap { lookup[$0] }
        let remaining = providers.filter { p in !orderedIDs.contains(p.id) }
        providers = reordered + remaining
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
        isPolling = true
        notificationManager.purgeStaleEntries()

        // Show progress for slow fetchers (xAI uses a headless browser)
        for (index, provider) in providers.enumerated() {
            if disabledProviderIDs.contains(provider.id) { continue }
            if provider.fetcherType == .xai && !XAIFetcher.hasCachedResult {
                providers[index].statusDetail = "Launching browser..."
            }
        }

        await withTaskGroup(of: (Int, ServiceStatus, [Incident], [ServiceComponent]).self) { group in
            for (index, provider) in providers.enumerated() {
                guard !disabledProviderIDs.contains(provider.id) else { continue }
                let fetcherType = provider.fetcherType
                let baseURL = provider.apiBaseURL
                group.addTask {
                    let status: ServiceStatus
                    let incidents: [Incident]
                    let components: [ServiceComponent]

                    switch fetcherType {
                    case .statuspage:
                        async let s = StatusFetcher.fetchStatus(baseURL: baseURL)
                        async let i = StatusFetcher.fetchIncidents(baseURL: baseURL)
                        async let c = StatusFetcher.fetchComponents(baseURL: baseURL)
                        let response = await s
                        status = response.map { ServiceStatus(fromIndicator: $0.status.indicator) } ?? .unknown
                        incidents = await i
                        components = await c
                    case .groq:
                        async let s = GroqFetcher.fetchStatus(baseURL: baseURL)
                        async let i = GroqFetcher.fetchIncidents(baseURL: baseURL)
                        status = await s
                        incidents = await i
                        components = []
                    case .google:
                        async let s = GoogleFetcher.fetchStatus(baseURL: baseURL)
                        async let i = GoogleFetcher.fetchIncidents(baseURL: baseURL)
                        status = await s
                        incidents = await i
                        components = []
                    case .htmlStatus:
                        async let s = HTMLStatusFetcher.fetchStatus(baseURL: baseURL)
                        async let i = HTMLStatusFetcher.fetchIncidents(baseURL: baseURL)
                        async let c = HTMLStatusFetcher.fetchComponents(baseURL: baseURL)
                        status = await s
                        incidents = await i
                        components = await c
                    case .xai:
                        async let s = XAIFetcher.fetchStatus(baseURL: baseURL)
                        async let i = XAIFetcher.fetchIncidents(baseURL: baseURL)
                        status = await s
                        incidents = await i
                        components = []
                    }

                    return (index, status, incidents, components)
                }
            }

            for await (index, status, incidents, components) in group {
                let previousStatus = providers[index].currentStatus
                providers[index].currentStatus = status
                providers[index].incidents = incidents
                providers[index].components = components
                providers[index].lastChecked = Date()
                providers[index].statusDetail = (status == .unknown) ? "Unable to fetch status" : nil

                // Notify only for the prioritized provider (or all)
                guard notificationsEnabled else { continue }
                let providerID = providers[index].id
                guard notifyProviderID == "all" || notifyProviderID == providerID else { continue }

                // Recovery notification: was degraded/outage, now operational
                if status == .operational
                    && previousStatus != .operational
                    && previousStatus != .unknown {
                    await notificationManager.sendRecoveryNotification(
                        providerName: providers[index].name,
                        providerID: providerID
                    )
                }

                for incident in incidents where incident.isActive {
                    await notificationManager.sendIncidentNotification(
                        providerName: providers[index].name,
                        providerID: providerID,
                        incident: incident
                    )
                }
            }
        }

        lastFullCheck = Date()
        isPolling = false
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

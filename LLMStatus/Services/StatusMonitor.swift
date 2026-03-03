import Foundation

@Observable
class StatusMonitor {
    var providers: [ServiceProvider]
    let notificationManager = NotificationManager()
    var notificationsEnabled = true
    private var pollingTask: Task<Void, Never>?

    /// Worst status across all providers (highest severity wins).
    var aggregatedStatus: ServiceStatus {
        guard !providers.isEmpty else { return .unknown }
        return providers
            .map(\.currentStatus)
            .max(by: { $0.severity < $1.severity }) ?? .unknown
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

    func fetchAllStatuses() async {
        await withTaskGroup(of: (Int, ServiceStatus, [Incident]).self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask {
                    async let statusResponse = StatusFetcher.fetchStatus(baseURL: provider.apiBaseURL)
                    async let incidents = StatusFetcher.fetchIncidents(baseURL: provider.apiBaseURL)

                    let status: ServiceStatus
                    if let response = await statusResponse {
                        status = ServiceStatus(fromIndicator: response.status.indicator)
                    } else {
                        status = .unknown
                    }

                    return (index, status, await incidents)
                }
            }

            for await (index, status, incidents) in group {
                providers[index].currentStatus = status
                providers[index].incidents = incidents
                providers[index].lastChecked = Date()

                // Notify for new/changed incidents (if enabled)
                guard notificationsEnabled else { continue }
                for incident in incidents where incident.isActive {
                    await notificationManager.sendIncidentNotification(
                        providerName: providers[index].name,
                        providerID: providers[index].id,
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
                statusURL: URL(string: "https://status.anthropic.com")!,
                apiBaseURL: URL(string: "https://status.anthropic.com/api/v2")!,
                currentStatus: .unknown,
                lastChecked: nil,
                incidents: []
            ),
            ServiceProvider(
                id: "openai",
                name: "OpenAI",
                statusURL: URL(string: "https://status.openai.com")!,
                apiBaseURL: URL(string: "https://status.openai.com/api/v2")!,
                currentStatus: .unknown,
                lastChecked: nil,
                incidents: []
            ),
        ]
    }
}

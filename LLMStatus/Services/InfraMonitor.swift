import Foundation

/// Websites and servers set up in Settings > Monitors, each polled on its own interval.
/// Owned by `StatusMonitor.infra`; a status change sends a notification (down, worse, recovered).
@Observable
class InfraMonitor {
    var websites: [WebsiteMonitor] = []
    var servers: [ServerMonitor] = []
    /// Last check per website or server id.
    var results: [UUID: CheckResult] = [:]
    /// Ids being checked right now.
    var checking: Set<UUID> = []
    var notificationsEnabled = true
    var websiteInterval: TimeInterval = 60 {
        didSet { if websiteInterval != oldValue, websiteTask != nil { startPolling() } }
    }
    var serverInterval: TimeInterval = 300 {
        didSet { if serverInterval != oldValue, serverTask != nil { startPolling() } }
    }
    /// Checks are skipped while this Mac is offline: a site is not down because the Wi-Fi is.
    @ObservationIgnored var isOnline: () -> Bool = { true }
    @ObservationIgnored private let notifications = NotificationManager()
    @ObservationIgnored private var websiteTask: Task<Void, Never>?
    @ObservationIgnored private var serverTask: Task<Void, Never>?

    var enabledWebsites: [WebsiteMonitor] { websites.filter(\.enabled) }
    var enabledServers: [ServerMonitor] { servers.filter(\.enabled) }

    /// Issues first, then the order of Settings.
    func ordered<T: Identifiable>(_ items: [T]) -> [T] where T.ID == UUID {
        let bad = items.filter { (results[$0.id]?.status.severity ?? 0) >= 2 }
        return bad + items.filter { (results[$0.id]?.status.severity ?? 0) < 2 }
    }

    /// Worst problem among enabled monitors, nil when none has one (unknown does not count).
    var issueStatus: ServiceStatus? {
        let ids = enabledWebsites.map(\.id) + enabledServers.map(\.id)
        return ids.compactMap { results[$0]?.status }
            .filter { $0.severity >= 2 }
            .max { $0.severity < $1.severity }
    }

    // MARK: - Polling

    func startPolling() {
        websiteTask?.cancel()
        serverTask?.cancel()
        websiteTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.checkWebsites()
                try? await Task.sleep(for: .seconds(self.websiteInterval))
            }
        }
        serverTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.checkServers()
                try? await Task.sleep(for: .seconds(self.serverInterval))
            }
        }
    }

    func refreshAll() async {
        async let sites: Void = checkWebsites()
        async let hosts: Void = checkServers()
        _ = await (sites, hosts)
    }

    @MainActor
    func checkWebsites() async {
        guard isOnline() else { return }
        await withTaskGroup(of: (WebsiteMonitor, CheckResult).self) { group in
            for site in enabledWebsites where !checking.contains(site.id) {
                checking.insert(site.id)
                group.addTask { (site, await WebsiteChecker.check(site)) }
            }
            for await (site, result) in group {
                checking.remove(site.id)
                await publish(result, id: site.id, name: site.name)
            }
        }
    }

    @MainActor
    func checkServers() async {
        guard isOnline() else { return }
        await withTaskGroup(of: (ServerMonitor, CheckResult).self) { group in
            for server in enabledServers where !checking.contains(server.id) {
                checking.insert(server.id)
                group.addTask { (server, await ServerChecker.check(server)) }
            }
            for await (server, result) in group {
                checking.remove(server.id)
                await publish(result, id: server.id, name: server.displayName)
            }
        }
    }

    /// Checks one monitor now (after it is added or edited in Settings).
    @MainActor
    func check(id: UUID) async {
        guard !checking.contains(id) else { return }
        if let site = websites.first(where: { $0.id == id }), site.enabled {
            checking.insert(id)
            let result = await WebsiteChecker.check(site)
            checking.remove(id)
            await publish(result, id: id, name: site.name)
        } else if let server = servers.first(where: { $0.id == id }), server.enabled {
            checking.insert(id)
            let result = await ServerChecker.check(server)
            checking.remove(id)
            await publish(result, id: id, name: server.displayName)
        }
    }

    /// Results of removed monitors go away with them.
    func prune() {
        let ids = Set(websites.map(\.id) + servers.map(\.id))
        for id in results.keys where !ids.contains(id) { results[id] = nil }
    }

    // MARK: - Notifications

    @MainActor
    private func publish(_ result: CheckResult, id: UUID, name: String) async {
        // Removed while its check was in flight.
        guard websites.contains(where: { $0.id == id }) || servers.contains(where: { $0.id == id }) else { return }
        let previous = results[id]?.status
        results[id] = result
        guard notificationsEnabled, let message = Self.alert(name: name, previous: previous, result: result) else { return }
        await notifications.sendMonitorNotification(title: message.title, body: message.body, identifier: "monitor-\(id)")
    }

    /// Down or worse than before, or back to operational after a problem. Unknown never alerts.
    static func alert(name: String, previous: ServiceStatus?, result: CheckResult) -> (title: String, body: String)? {
        let old = previous?.severity ?? 0, new = result.status.severity
        if new >= 2, new > old {
            let problems = result.problems.prefix(3).map { "\($0.name): \($0.value)" }
            return ("\(name): \(result.status.label)", problems.isEmpty ? result.summary : problems.joined(separator: " · "))
        }
        if result.status == .operational, old >= 2 {
            return ("\(name): Recovered", result.summary)
        }
        return nil
    }
}

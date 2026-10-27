import Foundation

/// Subscription usage limits (Claude plan, ChatGPT plan used by Codex).
struct SubscriptionUsage: Identifiable, Equatable {
    struct Window: Equatable {
        /// 0...100
        let percent: Double
        let resetsAt: Date?
        /// Window length; drives the label ("5h", "weekly").
        var seconds: Int?

        var label: String {
            switch seconds {
            case nil: "short"
            case let s? where s == 7 * 24 * 3600: "weekly"
            case let s? where s % (24 * 3600) == 0: "\(s / (24 * 3600))d"
            case let s?: "\(max(1, (s + 1800) / 3600))h"
            }
        }
    }

    enum Kind: String, CaseIterable {
        case claude, codex

        var name: String {
            switch self {
            case .claude: "Claude"
            case .codex: "Codex"
            }
        }

        /// What the local-log breakdown cannot see.
        var breakdownCaveat: String {
            switch self {
            case .claude: "claude.ai (web, mobile) and other devices are not included."
            case .codex: "Codex cloud tasks and machines not listed in Settings are not included."
            }
        }

        var dashboardURL: URL {
            switch self {
            case .claude: URL(string: "https://claude.ai/settings/usage")!
            case .codex: URL(string: "https://chatgpt.com/codex/settings/usage")!
            }
        }
    }

    let kind: Kind
    var weekly: Window?
    /// Shorter rolling window (5 h today) when the plan has one.
    var session: Window?
    var plan: String?
    /// Set when usage could not be read; shown instead of the gauges.
    var error: String?
    /// Estimated split of the weekly window by app, then project (local logs, plus remote hosts for Codex).
    var breakdown: [UsageShare] = []
    /// Remote hosts that could not be read for the breakdown.
    var breakdownErrors: [String] = []

    var id: String { kind.rawValue }
}

/// Reads the OAuth tokens the official CLIs already store locally. Never refreshes them:
/// rotating a refresh token here would sign the CLI out.
enum UsageFetcher {
    static let claudeURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let codexURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let weekSeconds = 7 * 24 * 3600

    static func fetch(_ kind: SubscriptionUsage.Kind) async -> SubscriptionUsage {
        switch kind {
        case .claude: await fetchClaude()
        case .codex: await fetchCodex()
        }
    }

    // MARK: - Claude

    private struct ClaudeCredentials: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let expiresAt: Double?
            let subscriptionType: String?
        }
        let claudeAiOauth: OAuth?
    }

    private struct ClaudeResponse: Decodable {
        struct Limit: Decodable {
            let utilization: Double?
            let resets_at: String?
        }
        let five_hour: Limit?
        let seven_day: Limit?
    }

    static func fetchClaude() async -> SubscriptionUsage {
        var usage = SubscriptionUsage(kind: .claude)
        // The `security` CLI is on the item's ACL (Claude Code writes it that way), so no keychain prompt.
        guard let raw = runSecurity(["find-generic-password", "-s", "Claude Code-credentials", "-w"]),
              let oauth = try? JSONDecoder().decode(ClaudeCredentials.self, from: raw).claudeAiOauth
        else {
            usage.error = "Sign in to Claude Code"
            return usage
        }
        usage.plan = oauth.subscriptionType?.capitalized
        if let expiresAt = oauth.expiresAt, Date(timeIntervalSince1970: expiresAt / 1000) < Date() {
            usage.error = "Token expired, open Claude Code"
            return usage
        }
        var request = URLRequest(url: claudeURL)
        request.setValue("Bearer \(oauth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        guard let data = await send(request, usage: &usage, relogin: "open Claude Code") else { return usage }
        return parseClaude(data, into: usage)
    }

    static func parseClaude(_ data: Data, into base: SubscriptionUsage = SubscriptionUsage(kind: .claude)) -> SubscriptionUsage {
        var usage = base
        guard let response = try? JSONDecoder().decode(ClaudeResponse.self, from: data),
              let weekly = window(response.seven_day) else {
            usage.error = "Unreadable usage data"
            return usage
        }
        usage.weekly = weekly
        usage.session = window(response.five_hour, seconds: 5 * 3600)
        return usage
    }

    private static func window(_ limit: ClaudeResponse.Limit?, seconds: Int = weekSeconds) -> SubscriptionUsage.Window? {
        guard let percent = limit?.utilization else { return nil }
        return .init(percent: percent, resetsAt: limit?.resets_at.flatMap(parseISODate), seconds: seconds)
    }

    // MARK: - Codex

    private struct CodexAuth: Decodable {
        struct Tokens: Decodable {
            let access_token: String
            let account_id: String?
        }
        let tokens: Tokens?
    }

    private struct CodexResponse: Decodable {
        struct RateLimit: Decodable {
            let primary_window: Window?
            let secondary_window: Window?
        }
        struct Window: Decodable {
            let used_percent: Double
            let limit_window_seconds: Int?
            let reset_at: Double?
        }
        let plan_type: String?
        let rate_limit: RateLimit?
    }

    private static func codexTokens() -> CodexAuth.Tokens? {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        guard let raw = try? Data(contentsOf: home.appendingPathComponent("auth.json")) else { return nil }
        return try? JSONDecoder().decode(CodexAuth.self, from: raw).tokens
    }

    /// ChatGPT account of the local Codex login: remote hosts only count usage of this account.
    static func codexAccountID() -> String? { codexTokens()?.account_id }

    static func fetchCodex() async -> SubscriptionUsage {
        var usage = SubscriptionUsage(kind: .codex)
        guard let tokens = codexTokens() else {
            usage.error = "Sign in to Codex with ChatGPT"
            return usage
        }
        var request = URLRequest(url: codexURL)
        request.setValue("Bearer \(tokens.access_token)", forHTTPHeaderField: "Authorization")
        if let account = tokens.account_id {
            request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        guard let data = await send(request, usage: &usage, relogin: "run codex") else { return usage }
        return parseCodex(data, into: usage)
    }

    static func parseCodex(_ data: Data, into base: SubscriptionUsage = SubscriptionUsage(kind: .codex)) -> SubscriptionUsage {
        var usage = base
        guard let response = try? JSONDecoder().decode(CodexResponse.self, from: data) else {
            usage.error = "Unreadable usage data"
            return usage
        }
        usage.plan = response.plan_type?.capitalized
        // Primary/secondary are not fixed: a plan may only have a weekly window, sent as primary.
        let windows = [response.rate_limit?.primary_window, response.rate_limit?.secondary_window].compactMap { $0 }
        func convert(_ w: CodexResponse.Window) -> SubscriptionUsage.Window {
            .init(percent: w.used_percent, resetsAt: w.reset_at.map { Date(timeIntervalSince1970: $0) },
                  seconds: w.limit_window_seconds)
        }
        guard let weekly = windows.first(where: { ($0.limit_window_seconds ?? 0) >= weekSeconds }) else {
            usage.error = windows.isEmpty ? "No usage limit reported" : "No weekly limit reported"
            usage.session = windows.first.map(convert)
            return usage
        }
        usage.weekly = convert(weekly)
        usage.session = windows.first { ($0.limit_window_seconds ?? 0) < weekSeconds }.map(convert)
        return usage
    }

    // MARK: - Helpers

    private static func send(_ request: URLRequest, usage: inout SubscriptionUsage, relogin: String) async -> Data? {
        let source = "UsageFetcher.\(usage.kind.rawValue)"
        do {
            let (data, response) = try await HTTPClient.session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 403 {
                usage.error = "Session expired, \(relogin)"
                return nil
            }
            guard (200...299).contains(code) else {
                FileLogger.shared.warning("HTTP \(code)", source: source)
                usage.error = "Usage unavailable (HTTP \(code))"
                return nil
            }
            return data
        } catch {
            FileLogger.shared.error("Fetch failed: \(error.localizedDescription)", source: source)
            usage.error = "Usage unavailable"
            return nil
        }
    }

    private static func runSecurity(_ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // A locked keychain makes `security` wait for the user; never let that hold the refresh.
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if process.isRunning { process.terminate() }
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    // Creating a formatter costs far more than parsing: the log scan parses tens of thousands of dates.
    // ISO8601DateFormatter is thread-safe once configured.
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plainFormatter = ISO8601DateFormatter()

    static func parseISODate(_ value: String) -> Date? {
        if let date = fractionalFormatter.date(from: value) ?? plainFormatter.date(from: value) { return date }
        // Python-style microseconds (".196176") are rejected by ISO8601DateFormatter; keep milliseconds.
        let trimmed = value.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        return fractionalFormatter.date(from: trimmed)
    }
}

/// Keeps subscription usage fresh. Polled less often than status pages: limits move slowly.
@Observable
class UsageMonitor {
    var usages: [SubscriptionUsage] = []
    var enabledKinds: Set<SubscriptionUsage.Kind> = Set(SubscriptionUsage.Kind.allCases)
    /// SSH hosts (aliases from ~/.ssh/config) whose Codex usage joins the breakdown.
    var remoteHosts: [String] = [] {
        didSet { if remoteHosts != oldValue { generation += 1 } }
    }
    /// Bumped when settings change: a refresh started before must not publish its breakdown.
    @ObservationIgnored private var generation = 0
    private var pollingTask: Task<Void, Never>?

    var visibleUsages: [SubscriptionUsage] {
        usages.filter { enabledKinds.contains($0.kind) }
    }

    func startPolling(interval: TimeInterval = 300) {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    @MainActor
    func refresh() async {
        let kinds = SubscriptionUsage.Kind.allCases.filter { enabledKinds.contains($0) }
        await withTaskGroup(of: SubscriptionUsage.self) { group in
            for kind in kinds { group.addTask { await UsageFetcher.fetch(kind) } }
            // Publish each subscription as soon as it lands, replacing only its own row,
            // so overlapping refreshes (poll, Refresh, toggle) never drop another row.
            for await result in group {
                var result = result
                if let previous = usages.first(where: { $0.kind == result.kind }) {
                    result.breakdown = previous.breakdown
                    result.breakdownErrors = previous.breakdownErrors
                }
                publish(result)
            }
        }
        // The log scan takes seconds on a cold cache: percentages show first, the split follows.
        let started = generation
        for kind in kinds {
            guard let weekly = usages.first(where: { $0.kind == kind })?.weekly else { continue }
            let length = TimeInterval(weekly.seconds ?? 7 * 24 * 3600)
            let start = (weekly.resetsAt ?? Date()).addingTimeInterval(-length)
            var remote = [RemoteUsage.Result]()
            if kind == .codex, !remoteHosts.isEmpty {
                let hosts = remoteHosts, account = UsageFetcher.codexAccountID()
                // ssh blocks; run every host concurrently off the main actor.
                remote = await withTaskGroup(of: RemoteUsage.Result.self) { group in
                    for host in hosts {
                        group.addTask { RemoteUsage.fetch(host: host, since: start, accountID: account) }
                    }
                    return await group.reduce(into: []) { $0.append($1) }
                }
            }
            let shares = await UsageBreakdown.shared.shares(
                for: kind, since: start, extra: remote.flatMap(\.records)
            )
            guard started == generation else { return }
            if let index = usages.firstIndex(where: { $0.kind == kind }) {
                usages[index].breakdown = shares
                usages[index].breakdownErrors = remote.compactMap(\.error)
            }
        }
    }

    private func publish(_ usage: SubscriptionUsage) {
        let order = SubscriptionUsage.Kind.allCases
        usages.removeAll { $0.kind == usage.kind }
        usages.append(usage)
        usages.sort { order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)! }
    }
}

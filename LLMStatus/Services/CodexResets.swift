import Foundation

/// Free rate limit resets granted to the ChatGPT account of this Mac's Codex login: the same
/// endpoints the Codex CLI uses (`/wham/rate-limit-reset-credits`, then `.../consume`).
/// Listing is read-only; using one restores the Codex 5h and weekly limits and cannot be undone.
enum CodexResets {
    struct Credit: Equatable, Identifiable {
        let id: String
        let title: String
        let expiresAt: Date?
    }

    static let listURL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!
    static let consumeURL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume")!

    private struct ListResponse: Decodable {
        struct Item: Decodable {
            let id: String
            let reset_type: String?
            let is_supported_by_plan: Bool?
            let status: String?
            let expires_at: String?
            let title: String?
        }
        let credits: [Item]?
    }

    /// Available resets for Codex, soonest to expire first; nil when they could not be read.
    static func fetch() async -> [Credit]? {
        guard let request = request(listURL) else { return nil }
        guard let (data, response) = try? await HTTPClient.session.data(for: request),
              let code = (response as? HTTPURLResponse)?.statusCode, (200...299).contains(code) else {
            FileLogger.shared.warning("Reset credits unavailable", source: "CodexResets")
            return nil
        }
        return parse(data)
    }

    static func parse(_ data: Data, now: Date = Date()) -> [Credit]? {
        guard let response = try? JSONDecoder().decode(ListResponse.self, from: data) else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return (response.credits ?? [])
            .filter { $0.status == "available" && $0.is_supported_by_plan != false
                && ($0.reset_type ?? "codex_rate_limits").hasPrefix("codex") }
            .map { item in
                let expiry = item.expires_at.flatMap { iso.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
                return Credit(id: item.id, title: item.title ?? "Reset", expiresAt: expiry)
            }
            .filter { ($0.expiresAt ?? .distantFuture) > now }
            .sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
    }

    /// Uses one reset. Nil on success, else a short reason. The request id makes a retried
    /// request count once.
    static func consume(_ creditID: String) async -> String? {
        guard var request = request(consumeURL) else { return "Sign in to Codex with ChatGPT" }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "credit_id": creditID,
            "redeem_request_id": "consume-rate-limit-reset-" + UUID().uuidString.lowercased(),
        ])
        do {
            let (data, response) = try await HTTPClient.session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(code) else {
                let detail = String(decoding: data.prefix(300), as: UTF8.self)
                FileLogger.shared.error("Reset consume HTTP \(code): \(detail)", source: "CodexResets")
                return code == 401 || code == 403 ? "Session expired, run codex" : "Reset refused (HTTP \(code))"
            }
            return nil
        } catch {
            FileLogger.shared.error("Reset consume failed: \(error.localizedDescription)", source: "CodexResets")
            return "Reset failed: \(error.localizedDescription)"
        }
    }

    private static func request(_ url: URL) -> URLRequest? {
        guard let tokens = UsageFetcher.codexTokens() else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(tokens.access_token)", forHTTPHeaderField: "Authorization")
        if let account = tokens.account_id {
            request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        return request
    }
}

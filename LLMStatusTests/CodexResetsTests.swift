import Testing
import Foundation
@testable import LLMStatus

@Suite("Codex resets")
struct CodexResetsTests {
    let response = """
    {"credits": [
      {"id": "RateLimitResetCredit_b", "reset_type": "codex_rate_limits", "is_supported_by_plan": true, "status": "available",
       "expires_at": "2026-11-06T22:10:49.684357Z", "title": "Full reset"},
      {"id": "RateLimitResetCredit_a", "reset_type": "codex_rate_limits", "is_supported_by_plan": true, "status": "available",
       "expires_at": "2026-10-29T18:35:32.248365Z", "title": "Full reset"},
      {"id": "RateLimitResetCredit_used", "reset_type": "codex_rate_limits", "is_supported_by_plan": true, "status": "redeemed",
       "expires_at": "2026-11-20T00:00:00Z", "title": "Full reset"},
      {"id": "RateLimitResetCredit_plan", "reset_type": "codex_rate_limits", "is_supported_by_plan": false, "status": "available",
       "expires_at": "2026-11-20T00:00:00Z", "title": "Full reset"}
    ], "available_count": 2}
    """

    @Test("Available resets only, soonest to expire first")
    func parse() throws {
        let now = ISO8601DateFormatter().date(from: "2026-10-29T15:00:00Z")!
        let credits = try #require(CodexResets.parse(Data(response.utf8), now: now))
        #expect(credits.map(\.id) == ["RateLimitResetCredit_a", "RateLimitResetCredit_b"])
        #expect(credits.first?.title == "Full reset")
    }

    @Test("Expired resets are dropped")
    func expired() {
        let now = ISO8601DateFormatter().date(from: "2026-10-30T00:00:00Z")!
        #expect(CodexResets.parse(Data(response.utf8), now: now)?.map(\.id) == ["RateLimitResetCredit_b"])
    }

    @Test("Unreadable answer is unknown, not zero resets")
    func unreadable() {
        #expect(CodexResets.parse(Data("<html>".utf8)) == nil)
    }
}

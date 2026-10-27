import Foundation
import Testing
@testable import LLMStatus

@Suite("Subscription usage")
struct UsageFetcherTests {
    @Test("Claude weekly and 5 h limits are read, microsecond dates included")
    func claude() {
        let body = #"{"five_hour":{"utilization":1.0,"resets_at":"2026-10-27T20:00:00.196176+00:00"},"seven_day":{"utilization":33.0,"resets_at":"2026-10-31T23:00:00.196198+00:00"},"seven_day_opus":null}"#
        let usage = UsageFetcher.parseClaude(Data(body.utf8))
        #expect(usage.error == nil)
        #expect(usage.weekly?.percent == 33)
        #expect(usage.session?.percent == 1)
        let expected = ISO8601DateFormatter().date(from: "2026-10-31T23:00:00Z")!
        #expect(abs(usage.weekly!.resetsAt!.timeIntervalSince(expected) - 0.196) < 0.001)
    }

    @Test("Claude response without a weekly limit is an error, not 0 %")
    func claudeMissing() {
        let usage = UsageFetcher.parseClaude(Data(#"{"five_hour":null,"seven_day":null}"#.utf8))
        #expect(usage.weekly == nil)
        #expect(usage.error != nil)
    }

    @Test("Codex weekly window is found whether sent as primary or secondary")
    func codexWindows() {
        let weeklyOnly = #"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":4,"limit_window_seconds":604800,"reset_after_seconds":496591,"reset_at":1793610049},"secondary_window":null}}"#
        let a = UsageFetcher.parseCodex(Data(weeklyOnly.utf8))
        #expect(a.weekly?.percent == 4)
        #expect(a.session == nil)
        #expect(a.plan == "Pro")
        #expect(a.weekly?.resetsAt == Date(timeIntervalSince1970: 1793610049))

        let both = #"{"rate_limit":{"primary_window":{"used_percent":12,"limit_window_seconds":18000,"reset_at":1},"secondary_window":{"used_percent":40,"limit_window_seconds":604800,"reset_at":2}}}"#
        let b = UsageFetcher.parseCodex(Data(both.utf8))
        #expect(b.weekly?.percent == 40)
        #expect(b.weekly?.label == "weekly")
        #expect(b.session?.percent == 12)
        #expect(b.session?.label == "5h")
    }

    @Test("Codex without a weekly window reports it instead of inventing one")
    func codexNoWeekly() {
        let body = #"{"rate_limit":{"primary_window":{"used_percent":12,"limit_window_seconds":18000},"secondary_window":null}}"#
        let usage = UsageFetcher.parseCodex(Data(body.utf8))
        #expect(usage.weekly == nil)
        #expect(usage.error == "No weekly limit reported")
        #expect(UsageFetcher.parseCodex(Data("<html>".utf8)).error == "Unreadable usage data")
    }

    @Test("Window labels follow the server-provided duration", arguments: [
        (3600, "1h"), (18000, "5h"), (604800, "weekly"), (2592000, "30d")
    ])
    func windowLabel(value: (Int, String)) {
        #expect(SubscriptionUsage.Window(percent: 0, resetsAt: nil, seconds: value.0).label == value.1)
    }
}

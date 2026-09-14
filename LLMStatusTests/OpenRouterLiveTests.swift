import Foundation
import Testing
@testable import LLMStatus

@Suite("OpenRouter live verification")
struct OpenRouterLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LLMSTATUS_LIVE_OPENROUTER"] == "1"))
    func currentStatusThroughMonitor() async throws {
        let monitor = StatusMonitor()
        monitor.notificationsEnabled = false
        monitor.disabledProviderIDs = Set(monitor.providers.map(\.id).filter { $0 != "openrouter" })
        await monitor.fetchAllStatuses()
        let provider = try #require(monitor.providers.first { $0.id == "openrouter" })
        print("OpenRouter live: \(provider.currentStatus.rawValue); groups/components: \(provider.components.count)")
        #expect(provider.currentStatus == .operational)
    }
}

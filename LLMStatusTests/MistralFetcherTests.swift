import Foundation
import Testing
@testable import LLMStatus

@Suite("HTML Status Fetcher")
struct HTMLStatusFetcherTests {

    @Test("'All Systems Operational' detected as operational")
    func operationalDetected() {
        let html = "<html><body><h1>All Systems Operational</h1></body></html>"
        let lower = html.lowercased()
        #expect(lower.contains("all systems operational"))
    }

    @Test("'All systems operational' (lowercase variant) detected")
    func operationalLowercaseDetected() {
        let html = "<html><body>All systems operational</body></html>"
        let lower = html.lowercased()
        #expect(lower.contains("all systems operational"))
    }

    @Test("'Major Outage' detected")
    func majorOutageDetected() {
        let html = "<html><body><span>Major Outage</span></body></html>"
        let lower = html.lowercased()
        #expect(lower.contains("major outage"))
    }

    @Test("'Degraded' detected")
    func degradedDetected() {
        let html = "<html><body>Service Degraded Performance</body></html>"
        let lower = html.lowercased()
        #expect(lower.contains("degraded"))
    }

    @Test("'Partial Outage' detected")
    func partialOutageDetected() {
        let html = "<html><body>Partial Outage on API</body></html>"
        let lower = html.lowercased()
        #expect(lower.contains("partial outage"))
    }
}

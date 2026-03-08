import Foundation
import Testing
@testable import LLMStatus

@Suite("Groq Fetcher Parsing")
struct GroqFetcherTests {

    @Test("Empty ongoing incidents → operational")
    func operationalWhenNoIncidents() throws {
        let json = """
        {"page_title":"Groq","page_url":"https://groqstatus.com/","ongoing_incidents":[],"in_progress_maintenances":[],"scheduled_maintenances":[]}
        """
        let summary = try JSONDecoder().decode(GroqFetcher.SummaryResponse.self, from: Data(json.utf8))
        #expect(summary.ongoingIncidents.isEmpty)
        #expect(summary.inProgressMaintenances.isEmpty)
    }

    @Test("Ongoing incident with degraded component parses correctly")
    func ongoingIncidentParsed() throws {
        let json = """
        {
          "page_title": "Groq",
          "page_url": "https://groqstatus.com/",
          "ongoing_incidents": [
            {
              "id": "inc-1",
              "name": "API Errors",
              "status": "identified",
              "url": "https://groqstatus.com/incidents/inc-1",
              "affected_components": [
                {
                  "id": "comp-1",
                  "name": "API",
                  "current_status": "degraded_performance"
                }
              ],
              "last_update_at": "2026-03-07T10:00:00Z",
              "last_update_message": "Investigating"
            }
          ],
          "in_progress_maintenances": [],
          "scheduled_maintenances": []
        }
        """
        let summary = try JSONDecoder().decode(GroqFetcher.SummaryResponse.self, from: Data(json.utf8))
        #expect(summary.ongoingIncidents.count == 1)
        let incident = try #require(summary.ongoingIncidents.first)
        #expect(incident.name == "API Errors")
        #expect(incident.affectedComponents?.first?.currentStatus == "degraded_performance")
    }

    @Test("Full outage component detected")
    func fullOutageComponentParsed() throws {
        let json = """
        {
          "page_title": "Groq",
          "page_url": "https://groqstatus.com/",
          "ongoing_incidents": [
            {
              "id": "inc-2",
              "name": "Total Outage",
              "status": "investigating",
              "affected_components": [
                {"id": "c1", "name": "API", "current_status": "full_outage"}
              ]
            }
          ],
          "in_progress_maintenances": [],
          "scheduled_maintenances": []
        }
        """
        let summary = try JSONDecoder().decode(GroqFetcher.SummaryResponse.self, from: Data(json.utf8))
        let statuses = summary.ongoingIncidents
            .flatMap { $0.affectedComponents ?? [] }
            .compactMap { $0.currentStatus }
        #expect(statuses.contains("full_outage"))
    }
}

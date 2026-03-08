import Foundation
import Testing
@testable import LLMStatus

@Suite("Google Fetcher Parsing")
struct GoogleFetcherTests {

    @Test("Active Gemini incident parsed correctly")
    func activeGeminiIncident() throws {
        let json = """
        [
          {
            "id": "abc123",
            "external_desc": "Gemini API errors",
            "status_impact": "SERVICE_DISRUPTION",
            "severity": "high",
            "affected_products": [
              {"title": "Vertex Gemini API", "id": "Z0FZJAMvEB4j3NbCJs6B"}
            ],
            "most_recent_update": {"status": "SERVICE_DISRUPTION"},
            "currently_affected_locations": [{"title": "us-central1", "id": "loc1"}],
            "begin": "2026-03-07T10:00:00+00:00",
            "end": null,
            "uri": "incidents/abc123"
          }
        ]
        """
        let incidents = try JSONDecoder().decode([GoogleFetcher.GoogleIncident].self, from: Data(json.utf8))
        #expect(incidents.count == 1)
        let inc = try #require(incidents.first)
        #expect(inc.severity == "high")
        #expect(inc.affectedProducts.first?.id == "Z0FZJAMvEB4j3NbCJs6B")
        #expect(inc.currentlyAffectedLocations?.isEmpty == false)
    }

    @Test("Resolved incident (empty affected locations) is not active")
    func resolvedIncidentFiltered() throws {
        let json = """
        [
          {
            "id": "resolved1",
            "external_desc": "Past issue",
            "status_impact": "SERVICE_INFORMATION",
            "severity": "low",
            "affected_products": [
              {"title": "Vertex Gemini API", "id": "Z0FZJAMvEB4j3NbCJs6B"}
            ],
            "most_recent_update": {"status": "AVAILABLE"},
            "currently_affected_locations": [],
            "begin": "2026-03-01T10:00:00+00:00",
            "end": "2026-03-01T12:00:00+00:00",
            "uri": "incidents/resolved1"
          }
        ]
        """
        let incidents = try JSONDecoder().decode([GoogleFetcher.GoogleIncident].self, from: Data(json.utf8))
        let active = incidents.filter { !(($0.currentlyAffectedLocations ?? []).isEmpty) }
        #expect(active.isEmpty)
    }

    @Test("Non-Gemini incident is ignored")
    func nonGeminiFiltered() throws {
        let json = """
        [
          {
            "id": "other1",
            "external_desc": "Cloud SQL issue",
            "status_impact": "SERVICE_DISRUPTION",
            "severity": "high",
            "affected_products": [
              {"title": "Cloud SQL", "id": "some-other-id"}
            ],
            "most_recent_update": {"status": "SERVICE_DISRUPTION"},
            "currently_affected_locations": [{"title": "us-east1", "id": "loc1"}],
            "begin": "2026-03-07T10:00:00+00:00",
            "end": null,
            "uri": "incidents/other1"
          }
        ]
        """
        let incidents = try JSONDecoder().decode([GoogleFetcher.GoogleIncident].self, from: Data(json.utf8))
        let geminiIDs: Set<String> = ["Z0FZJAMvEB4j3NbCJs6B"]
        let geminiIncidents = incidents.filter { inc in
            inc.affectedProducts.contains { geminiIDs.contains($0.id) }
        }
        #expect(geminiIncidents.isEmpty)
    }
}

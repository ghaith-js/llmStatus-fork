import Foundation
import Testing
@testable import LLMStatus

@Suite("StatusFetcher JSON Parsing")
struct StatusFetcherTests {

    // MARK: - StatusResponse parsing

    @Test("Parse status response with 'none' indicator → operational")
    func parseStatusNone() throws {
        let json = """
        {
            "page": { "id": "abc", "name": "Test", "url": "https://test.com" },
            "status": { "indicator": "none", "description": "All Systems Operational" }
        }
        """
        let response = try JSONDecoder().decode(StatusResponse.self, from: Data(json.utf8))
        #expect(response.status.indicator == "none")
        #expect(ServiceStatus(fromIndicator: response.status.indicator) == .operational)
    }

    @Test("Parse status response with 'minor' indicator → degraded")
    func parseStatusMinor() throws {
        let json = """
        {
            "page": { "id": "abc", "name": "Test", "url": "https://test.com" },
            "status": { "indicator": "minor", "description": "Minor Service Outage" }
        }
        """
        let response = try JSONDecoder().decode(StatusResponse.self, from: Data(json.utf8))
        #expect(ServiceStatus(fromIndicator: response.status.indicator) == .degraded)
    }

    @Test("Parse status response with 'major' indicator → majorOutage")
    func parseStatusMajor() throws {
        let json = """
        {
            "page": { "id": "abc", "name": "Test", "url": "https://test.com" },
            "status": { "indicator": "major", "description": "Major System Outage" }
        }
        """
        let response = try JSONDecoder().decode(StatusResponse.self, from: Data(json.utf8))
        #expect(ServiceStatus(fromIndicator: response.status.indicator) == .majorOutage)
    }

    @Test("Parse status response with 'critical' indicator → critical")
    func parseStatusCritical() throws {
        let json = """
        {
            "page": { "id": "abc", "name": "Test", "url": "https://test.com" },
            "status": { "indicator": "critical", "description": "Critical System Outage" }
        }
        """
        let response = try JSONDecoder().decode(StatusResponse.self, from: Data(json.utf8))
        #expect(ServiceStatus(fromIndicator: response.status.indicator) == .critical)
    }

    // MARK: - IncidentsResponse parsing

    @Test("Parse incidents response with active incident")
    func parseActiveIncident() throws {
        let json = """
        {
            "incidents": [
                {
                    "id": "inc-001",
                    "name": "Elevated API Errors",
                    "status": "investigating",
                    "impact": "major",
                    "created_at": "2025-01-15T10:00:00.000Z",
                    "resolved_at": null,
                    "shortlink": "https://stspg.io/abc",
                    "incident_updates": [
                        {
                            "id": "upd-001",
                            "status": "investigating",
                            "body": "We are investigating elevated errors.",
                            "created_at": "2025-01-15T10:05:00.000Z"
                        }
                    ]
                }
            ]
        }
        """
        let response = try JSONDecoder().decode(IncidentsResponse.self, from: Data(json.utf8))
        #expect(response.incidents.count == 1)

        let incident = try #require(response.incidents.first?.toIncident())
        #expect(incident.id == "inc-001")
        #expect(incident.name == "Elevated API Errors")
        #expect(incident.impact == .major)
        #expect(incident.status == .investigating)
        #expect(incident.isActive)
        #expect(incident.updates.count == 1)
        #expect(incident.updates.first?.body == "We are investigating elevated errors.")
    }

    @Test("Parse incidents response with resolved incident")
    func parseResolvedIncident() throws {
        let json = """
        {
            "incidents": [
                {
                    "id": "inc-002",
                    "name": "Dashboard Outage",
                    "status": "resolved",
                    "impact": "minor",
                    "created_at": "2025-01-14T08:00:00.000Z",
                    "resolved_at": "2025-01-14T09:30:00.000Z",
                    "shortlink": null,
                    "incident_updates": []
                }
            ]
        }
        """
        let response = try JSONDecoder().decode(IncidentsResponse.self, from: Data(json.utf8))
        let incident = try #require(response.incidents.first?.toIncident())
        #expect(!incident.isActive)
        #expect(incident.resolvedAt != nil)
        #expect(incident.impact == .minor)
    }

    // MARK: - Malformed JSON

    @Test("Malformed JSON returns nil when decoding StatusResponse")
    func malformedStatusJSON() {
        let json = "{ invalid json }"
        let result = try? JSONDecoder().decode(StatusResponse.self, from: Data(json.utf8))
        #expect(result == nil)
    }

    @Test("Malformed JSON returns empty array for incidents")
    func malformedIncidentsJSON() {
        let json = "not json at all"
        let result = try? JSONDecoder().decode(IncidentsResponse.self, from: Data(json.utf8))
        #expect(result == nil)
    }

    @Test("Incident with unknown impact value is skipped by toIncident()")
    func unknownImpactSkipped() throws {
        let json = """
        {
            "incidents": [
                {
                    "id": "inc-003",
                    "name": "Test",
                    "status": "investigating",
                    "impact": "catastrophic",
                    "created_at": "2025-01-15T10:00:00.000Z",
                    "resolved_at": null,
                    "shortlink": null,
                    "incident_updates": []
                }
            ]
        }
        """
        let response = try JSONDecoder().decode(IncidentsResponse.self, from: Data(json.utf8))
        let incident = response.incidents.first?.toIncident()
        #expect(incident == nil)
    }
}

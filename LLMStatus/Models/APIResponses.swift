import Foundation

/// DTO for /api/v2/status.json
struct StatusResponse: Codable {
    let page: PageInfo
    let status: StatusInfo

    struct PageInfo: Codable {
        let id: String
        let name: String
        let url: String
    }

    struct StatusInfo: Codable {
        let indicator: String
        let description: String
    }
}

/// DTO for /api/v2/components.json
struct ComponentsResponse: Codable {
    let components: [ComponentDTO]

    struct ComponentDTO: Codable {
        let id: String
        let name: String
        let status: String
        let groupId: String?
        let group: Bool?

        enum CodingKeys: String, CodingKey {
            case id, name, status
            case groupId = "group_id"
            case group
        }

        func toServiceComponent() -> ServiceComponent {
            ServiceComponent(
                id: id,
                name: name,
                status: ServiceStatus(fromComponentStatus: status)
            )
        }
    }
}

/// DTO for /api/v2/incidents/unresolved.json
struct IncidentsResponse: Codable {
    let incidents: [IncidentDTO]

    struct IncidentDTO: Codable {
        let id: String
        let name: String
        let status: String
        let impact: String
        let createdAt: String
        let resolvedAt: String?
        let shortlink: String?
        let incidentUpdates: [IncidentUpdateDTO]?

        enum CodingKeys: String, CodingKey {
            case id, name, status, impact, shortlink
            case createdAt = "created_at"
            case resolvedAt = "resolved_at"
            case incidentUpdates = "incident_updates"
        }

        /// Convert DTO to domain model.
        func toIncident() -> Incident? {
            guard let impact = IncidentImpact(rawValue: impact),
                  let status = IncidentStatus(rawValue: status) else {
                return nil
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            guard let created = formatter.date(from: createdAt) else {
                return nil
            }

            let resolved = resolvedAt.flatMap { formatter.date(from: $0) }
            let updates = (incidentUpdates ?? []).compactMap { $0.toIncidentUpdate() }

            return Incident(
                id: id,
                name: name,
                impact: impact,
                status: status,
                createdAt: created,
                resolvedAt: resolved,
                shortlink: shortlink,
                updates: updates,
                affectedComponents: []
            )
        }
    }

    struct IncidentUpdateDTO: Codable {
        let id: String
        let status: String
        let body: String
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id, status, body
            case createdAt = "created_at"
        }

        func toIncidentUpdate() -> IncidentUpdate? {
            guard let status = IncidentStatus(rawValue: status) else {
                return nil
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            guard let created = formatter.date(from: createdAt) else {
                return nil
            }

            return IncidentUpdate(
                id: id,
                status: status,
                body: body,
                createdAt: created
            )
        }
    }
}

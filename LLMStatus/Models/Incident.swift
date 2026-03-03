import Foundation

struct Incident: Identifiable, Codable {
    let id: String
    let name: String
    let impact: IncidentImpact
    let status: IncidentStatus
    let createdAt: Date
    let resolvedAt: Date?
    let shortlink: String?
    let updates: [IncidentUpdate]
    let affectedComponents: [String]

    var isActive: Bool { resolvedAt == nil }
}

enum IncidentImpact: String, Codable {
    case none, minor, major, critical
}

enum IncidentStatus: String, Codable {
    case investigating, identified, monitoring, resolved, postmortem
}

struct IncidentUpdate: Identifiable, Codable {
    let id: String
    let status: IncidentStatus
    let body: String
    let createdAt: Date
}

import Foundation

struct ServiceProvider: Identifiable, Codable {
    let id: String
    let name: String
    let shortName: String
    let statusURL: URL
    let apiBaseURL: URL
    var currentStatus: ServiceStatus
    var lastChecked: Date?
    var incidents: [Incident]
}

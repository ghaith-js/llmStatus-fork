import Foundation

enum FetcherType: String, Codable {
    case statuspage   // Anthropic, OpenAI, Moonshot, DeepSeek (Atlassian Statuspage API)
    case groq         // Groq (incident.io)
    case google       // Google Cloud (custom)
    case htmlStatus   // Mistral, OpenRouter (HTML keyword parsing)
    case xai          // xAI (WebKit fetcher, cached 10min)
}

struct ServiceComponent: Identifiable, Codable {
    let id: String
    let name: String
    var status: ServiceStatus
    var children: [ServiceComponent] = []

    /// True if this is a group header with children
    var isGroup: Bool { !children.isEmpty }
}

struct ServiceProvider: Identifiable, Codable {
    let id: String
    let name: String
    let shortName: String
    let statusURL: URL
    let apiBaseURL: URL
    let fetcherType: FetcherType
    var currentStatus: ServiceStatus
    var lastChecked: Date?
    var incidents: [Incident]
    var statusDetail: String?
    var components: [ServiceComponent] = []
}

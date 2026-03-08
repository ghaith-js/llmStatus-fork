import Foundation

enum FetcherType: String, Codable {
    case statuspage   // Anthropic, OpenAI, Moonshot, DeepSeek (Atlassian Statuspage API)
    case groq         // Groq (incident.io)
    case google       // Google Cloud (custom)
    case htmlStatus   // Mistral, OpenRouter (HTML keyword parsing)
    case xai          // xAI (Python StealthyFetcher, cached 10min)
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
}

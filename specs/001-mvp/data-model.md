# Data Model: LLM Status MVP

## Entities

### ServiceProvider
Un fournisseur de LLM à monitorer.

```swift
struct ServiceProvider: Identifiable, Codable {
    let id: String                    // "anthropic", "openai"
    let name: String                  // "Anthropic (Claude)", "OpenAI"
    let statusURL: URL                // https://status.claude.com
    let apiBaseURL: URL               // https://status.claude.com/api/v2
    var currentStatus: ServiceStatus  // overall status
    var lastChecked: Date?            // last successful check
    var incidents: [Incident]         // active incidents
}
```

### ServiceStatus
L'état global d'un provider, mappé depuis l'API Statuspage.

```swift
enum ServiceStatus: String, Codable, CaseIterable {
    case operational  // indicator: "none"
    case degraded     // indicator: "minor"
    case majorOutage  // indicator: "major"
    case critical     // indicator: "critical"
    case unknown      // fetch failed / no data

    var color: Color {
        switch self {
        case .operational: return .green
        case .degraded:    return .yellow
        case .majorOutage: return .orange
        case .critical:    return .red
        case .unknown:     return .gray
        }
    }

    var sfSymbol: String {
        switch self {
        case .operational: return "checkmark.circle.fill"
        case .degraded:    return "exclamationmark.triangle.fill"
        case .majorOutage: return "xmark.circle.fill"
        case .critical:    return "xmark.octagon.fill"
        case .unknown:     return "questionmark.circle.fill"
        }
    }

    init(fromIndicator indicator: String) {
        switch indicator {
        case "none":     self = .operational
        case "minor":    self = .degraded
        case "major":    self = .majorOutage
        case "critical": self = .critical
        default:         self = .unknown
        }
    }
}
```

### Incident
Un incident actif sur un provider.

```swift
struct Incident: Identifiable, Codable {
    let id: String                   // Statuspage incident ID
    let name: String                 // "Elevated errors in API"
    let impact: IncidentImpact       // minor/major/critical
    let status: IncidentStatus       // investigating/identified/monitoring/resolved
    let createdAt: Date
    let resolvedAt: Date?
    let shortlink: String?           // URL vers la page incident
    let updates: [IncidentUpdate]    // Timeline des updates
    let affectedComponents: [String] // ["API", "Dashboard"]

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
```

### NotificationRecord
Tracking des notifications envoyées pour éviter les doublons.

```swift
struct NotificationRecord: Codable {
    let incidentID: String     // "anthropic-abc123"
    let notifiedAt: Date
    let lastStatus: IncidentStatus
}
```

### AppSettings
Préférences utilisateur stockées dans UserDefaults.

```swift
@Observable
class AppSettings {
    @AppStorage("refreshInterval") var refreshInterval: TimeInterval = 300  // 5 min
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = true
}
```

## Relationships

```
ServiceProvider 1 ──── * Incident
Incident        1 ──── * IncidentUpdate
Incident        1 ──── 1 NotificationRecord (optional)
```

## State Transitions

### ServiceStatus lifecycle:
```
unknown → operational (first successful fetch)
operational → degraded → majorOutage → critical (escalation)
critical → majorOutage → degraded → operational (resolution)
any → unknown (fetch failure)
```

### Incident lifecycle:
```
investigating → identified → monitoring → resolved → postmortem
```

## API Response Mapping

### StatusResponse (from /api/v2/status.json)
```swift
struct StatusResponse: Codable {
    let page: PageInfo
    let status: StatusInfo

    struct PageInfo: Codable {
        let id: String
        let name: String
        let url: String
    }

    struct StatusInfo: Codable {
        let indicator: String  // "none", "minor", "major", "critical"
        let description: String
    }
}
```

### IncidentsResponse (from /api/v2/incidents/unresolved.json)
```swift
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
    }
}
```

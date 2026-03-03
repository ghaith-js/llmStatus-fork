# Research: LLM Status MVP

## Decision 1: RSS vs JSON API pour le status monitoring

### Decision: Utiliser l'API JSON Statuspage v2 (pas le RSS)

### Rationale:
Les deux providers (Anthropic et OpenAI) utilisent Atlassian Statuspage, qui expose une API JSON structurée en plus des flux RSS. L'API JSON est nettement plus pratique :
- Données structurées avec types clairs (`indicator`: none/minor/major/critical)
- Endpoint dédié pour les incidents non résolus (`/api/v2/incidents/unresolved.json`)
- Pas besoin de parser du XML ou d'extraire la sévérité depuis du HTML dans les descriptions RSS
- Pas de dépendance tierce (FeedKit) nécessaire

### Alternatives considered:
- **RSS/Atom feeds** — Disponibles mais contiennent du HTML dans les descriptions, pas de champ de sévérité structuré, nécessite FeedKit ou XMLParser
- **RSS avec FeedKit** — Librairie mature mais ajoute une dépendance pour un parsing qu'on peut faire nativement en JSON

### URLs concrètes:

| Provider | Status Summary | Incidents non résolus | RSS (backup) |
|----------|---------------|----------------------|--------------|
| **Anthropic/Claude** | `https://status.claude.com/api/v2/status.json` | `https://status.claude.com/api/v2/incidents/unresolved.json` | `https://status.claude.com/history.rss` |
| **OpenAI** | `https://status.openai.com/api/v2/status.json` | `https://status.openai.com/api/v2/incidents/unresolved.json` | `https://status.openai.com/feed.rss` |

Note : `status.anthropic.com` redirige (302) vers `status.claude.com`.

### Structure JSON — Status Summary:
```json
{
  "page": { "id": "...", "name": "OpenAI", "url": "https://status.openai.com/" },
  "status": {
    "indicator": "minor",
    "description": "Partial System Degradation"
  }
}
```

### Structure JSON — Incidents:
```json
{
  "incidents": [{
    "id": "abc123",
    "name": "Elevated errors in API",
    "status": "identified",
    "impact": "minor",
    "created_at": "2026-03-03T15:30:00Z",
    "resolved_at": null,
    "incident_updates": [{
      "status": "identified",
      "body": "We've identified the issue...",
      "created_at": "2026-03-03T15:35:00Z"
    }],
    "components": [{
      "name": "API",
      "status": "degraded_performance"
    }]
  }]
}
```

### Valeurs clés:
- **indicator/impact**: `none`, `minor`, `major`, `critical`
- **incident status**: `investigating`, `identified`, `monitoring`, `resolved`, `postmortem`
- **component status**: `operational`, `degraded_performance`, `major_outage`, `under_maintenance`

---

## Decision 2: Framework UI — MenuBarExtra

### Decision: SwiftUI MenuBarExtra avec style `.window`

### Rationale:
- API native SwiftUI depuis macOS 13 (Ventura)
- Style `.window` permet un popover riche (liste des services, détails incidents)
- Icône dynamique via SF Symbols (circle.fill avec couleur)
- Pas besoin d'AppKit NSStatusBar

### Pattern clé:
```swift
@main
struct LLMStatusApp: App {
    var body: some Scene {
        MenuBarExtra {
            StatusPopoverView()
                .frame(width: 320, height: 400)
        } label: {
            Image(systemName: statusIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
```

### Config pour app menu bar uniquement (pas de dock):
```xml
<!-- Info.plist -->
<key>LSUIElement</key>
<true/>
```

---

## Decision 3: Background Refresh

### Decision: Timer-based polling avec Swift Concurrency (Task.sleep)

### Rationale:
- Simple et fiable pour une app menu bar avec LSUIElement=true
- URLSession background tasks ne sont pas fiables pour les apps menu bar
- Swift async/await natif, pas de dépendance

### Pattern:
```swift
func startPolling(interval: TimeInterval = 300) {
    Task {
        while !Task.isCancelled {
            await fetchAllStatuses()
            try? await Task.sleep(for: .seconds(interval))
        }
    }
}
```

---

## Decision 4: Notifications macOS

### Decision: UNUserNotificationCenter avec identifiants déterministes pour dédupliquer

### Rationale:
- API standard macOS pour les notifications locales
- Identifiant unique par incident = remplacement automatique si re-notifié
- Permission request via `requestAuthorization(options: [.alert, .sound])`

### Déduplication:
```swift
let identifier = "\(provider.id)-\(incident.id)"
// UNNotificationCenter remplace automatiquement les notifications avec le même identifier
```

---

## Decision 5: Launch at Login

### Decision: SMAppService.mainApp (ServiceManagement framework)

### Rationale:
- API moderne depuis macOS 13 (même baseline que MenuBarExtra)
- Remplace LSSharedFileList (déprécié) et SMLoginItemSetEnabled
- Sync automatique avec System Settings > General > Login Items

---

## Decision 6: Stockage local

### Decision: UserDefaults pour les préférences, pas de persistence des incidents

### Rationale:
- MVP n'a besoin que de stocker : intervalle de refresh, launch at login, derniers incidents notifiés
- UserDefaults suffit pour ces données simples
- Pas besoin de CoreData/SQLite pour le MVP

---

## Decision 7: Minimum macOS version

### Decision: macOS 14 (Sonoma)

### Rationale:
- MenuBarExtra disponible depuis macOS 13, mais améliorations significatives en 14
- SwiftUI @Observable macro (macOS 14+) simplifie le state management
- SMAppService stable depuis macOS 13
- La grande majorité des devs cibles sont sur macOS 14+

---

*Researched: 2026-03-03*

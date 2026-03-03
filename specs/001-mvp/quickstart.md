# Quickstart: LLM Status MVP

## Prerequisites

- macOS 14+ (Sonoma)
- Xcode 15+
- Swift 5.9+

## Project Setup

1. **Créer un nouveau projet Xcode**
   - File → New → Project → macOS → App
   - Product Name: `LLMStatus`
   - Interface: SwiftUI
   - Language: Swift

2. **Configurer comme app menu bar**
   - Target → Info → Add `Application is agent (UIElement)` = `YES`
   - Supprimer `ContentView.swift` par défaut, remplacer par `StatusPopoverView`

3. **Structure du code**
   ```
   LLMStatus/
   ├── LLMStatusApp.swift          # @main, MenuBarExtra setup
   ├── Models/
   │   ├── ServiceProvider.swift    # Provider + ServiceStatus
   │   ├── Incident.swift           # Incident + Updates
   │   └── APIResponses.swift       # Statuspage JSON DTOs
   ├── Services/
   │   ├── StatusFetcher.swift      # URLSession + JSON decoding
   │   ├── StatusMonitor.swift      # Polling timer + state aggregation
   │   └── NotificationManager.swift # UNUserNotificationCenter
   ├── Views/
   │   ├── StatusPopoverView.swift  # Main popover (service list)
   │   ├── ServiceRowView.swift     # Individual service status row
   │   └── SettingsView.swift       # Refresh interval, launch at login
   └── Info.plist
   ```

## Build & Run

```bash
# Ouvrir dans Xcode
open LLMStatus.xcodeproj

# Ou build en CLI
xcodebuild -scheme LLMStatus -configuration Debug build
```

## Test local

Pour tester sans attendre un vrai incident :
1. Créer un mock JSON server avec les réponses Statuspage
2. Pointer les URLs des providers vers `localhost:8080`
3. Simuler un changement de status `none` → `major`
4. Vérifier que l'icône change et la notification est envoyée

## Configuration des providers (hardcoded pour MVP)

```swift
let providers: [ServiceProvider] = [
    ServiceProvider(
        id: "anthropic",
        name: "Anthropic (Claude)",
        statusURL: URL(string: "https://status.claude.com")!,
        apiBaseURL: URL(string: "https://status.claude.com/api/v2")!
    ),
    ServiceProvider(
        id: "openai",
        name: "OpenAI",
        statusURL: URL(string: "https://status.openai.com")!,
        apiBaseURL: URL(string: "https://status.openai.com/api/v2")!
    )
]
```

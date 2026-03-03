# Implementation Plan: LLM Status MVP

**Branch**: `001-mvp` | **Date**: 2026-03-03 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `.specify/specs/001-mvp/spec.md`

## Summary

App macOS native (SwiftUI) qui vit dans la menu bar et affiche le statut de disponibilité des services LLM (Anthropic/Claude, OpenAI) en temps réel. Utilise l'API JSON Statuspage v2 pour récupérer les statuts et incidents, avec notifications macOS natives lors de changements de status.

## Technical Context

**Language/Version**: Swift 5.9+ / macOS 14 (Sonoma)
**Primary Dependencies**: SwiftUI (MenuBarExtra), Foundation (URLSession, JSONDecoder), UserNotifications (UNUserNotificationCenter), ServiceManagement (SMAppService)
**Storage**: UserDefaults (préférences), in-memory (état des services)
**Testing**: XCTest (unit tests pour parsing JSON, state transitions, déduplication notifications)
**Target Platform**: macOS 14+ (Sonoma)
**Project Type**: desktop-app (menu bar utility)
**Performance Goals**: <50 MB RAM, 0% CPU en idle, refresh en <2s
**Constraints**: Pas de backend, pas de dépendances tierces, LSUIElement=true (pas de dock)
**Scale/Scope**: 2 providers (MVP), 1 popover view, 1 settings view

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Core Value — Status Visibility | PASS | Indicateur coloré menu bar = visibilité instantanée |
| II. Developer-First | PASS | App légère, pas de bloat, LSUIElement=true |
| III. Native & Progressive | PASS | 100% Swift/SwiftUI, zéro dépendance tierce |
| IV. Open Source + Donations | PASS | Pas de paywall, structure simple et lisible |
| V. Architecture extensible | PASS | ServiceProvider protocol permet d'ajouter des providers facilement |

## Project Structure

### Documentation (this feature)

```text
specs/001-mvp/
├── plan.md              # This file
├── research.md          # Technology decisions
├── data-model.md        # Swift entities and API mapping
├── quickstart.md        # Setup instructions
└── tasks.md             # Task breakdown (next step)
```

### Source Code (repository root)

```text
LLMStatus/
├── LLMStatusApp.swift              # @main entry, MenuBarExtra scene
├── Models/
│   ├── ServiceProvider.swift        # ServiceProvider, ServiceStatus enum
│   ├── Incident.swift               # Incident, IncidentUpdate, IncidentStatus
│   └── APIResponses.swift           # StatusResponse, IncidentsResponse DTOs
├── Services/
│   ├── StatusFetcher.swift          # URLSession calls to Statuspage API
│   ├── StatusMonitor.swift          # Polling timer, state aggregation, @Observable
│   └── NotificationManager.swift    # UNUserNotificationCenter, deduplication
├── Views/
│   ├── StatusPopoverView.swift      # Main popover: service list + last refresh
│   ├── ServiceRowView.swift         # Single service row with status indicator
│   ├── IncidentDetailView.swift     # Incident title + updates timeline
│   └── SettingsView.swift           # Refresh interval, launch at login, quit
└── Info.plist                       # LSUIElement=true

LLMStatusTests/
├── StatusFetcherTests.swift         # JSON parsing with mock responses
├── StatusMonitorTests.swift         # State transitions, aggregation logic
└── NotificationManagerTests.swift   # Deduplication logic
```

**Structure Decision**: Single project (Option 1 adapted for macOS app). Pas de backend, pas de frontend/backend split. Structure plate avec Models/Services/Views standard pour une app SwiftUI.

## Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                  LLMStatusApp                     │
│              (MenuBarExtra scene)                  │
│                                                   │
│  ┌─────────────┐    ┌──────────────────────────┐ │
│  │ StatusIcon   │    │  StatusPopoverView       │ │
│  │ (SF Symbol)  │    │  ├── ServiceRowView x N  │ │
│  │              │    │  ├── IncidentDetailView   │ │
│  └──────┬───────┘    │  └── SettingsView         │ │
│         │            └──────────┬───────────────┘ │
│         │                       │                  │
│  ┌──────▼───────────────────────▼──────────────┐  │
│  │           StatusMonitor (@Observable)         │  │
│  │  - providers: [ServiceProvider]               │  │
│  │  - aggregatedStatus: ServiceStatus            │  │
│  │  - startPolling() / stopPolling()             │  │
│  └──────────────┬──────────────────┬────────────┘  │
│                 │                  │                 │
│  ┌──────────────▼───────┐  ┌──────▼──────────────┐ │
│  │    StatusFetcher      │  │ NotificationManager │ │
│  │  - fetchStatus(URL)   │  │ - notify(incident)  │ │
│  │  - fetchIncidents(URL)│  │ - isDuplicate(id)   │ │
│  │  (URLSession + JSON)  │  │ (UNNotificationCtr) │ │
│  └───────────────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────┘
         │                           │
         ▼                           ▼
  Statuspage API v2           macOS Notification Center
  (status.json,               (local notifications)
   incidents/unresolved.json)
```

## Key Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Data source | JSON API (pas RSS) | Données structurées, pas de parsing XML/HTML |
| UI framework | SwiftUI MenuBarExtra (.window) | Natif, popover riche, SF Symbols dynamiques |
| State management | @Observable (macOS 14+) | Simplest, no Combine needed |
| Polling | Task.sleep loop | Fiable pour menu bar apps, pas de URLSession background |
| Notifications | UNUserNotificationCenter | Standard macOS, identifiants déterministes pour dédupliquer |
| Launch at login | SMAppService | API moderne, sync avec System Settings |
| Storage | UserDefaults (@AppStorage) | Suffisant pour préférences simples |
| Dependencies | Zéro | Constitution principle III, tout est natif |

## Complexity Tracking

> Aucune violation de constitution détectée. Pas de complexité à justifier.

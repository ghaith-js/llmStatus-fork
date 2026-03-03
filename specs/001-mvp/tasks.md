# Tasks: LLM Status MVP

**Input**: Design documents from `specs/001-mvp/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Included per constitution (III. Build Discipline: TDD pour la logique métier)

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1, US2, US3)
- Exact file paths based on plan.md project structure

---

## Phase 1: Setup (Project Initialization)

**Purpose**: Create Xcode project and basic SwiftUI menu bar app shell

- [ ] T001 Create Xcode project `LLMStatus` with SwiftUI lifecycle, target macOS 14+
- [ ] T002 Configure Info.plist with `LSUIElement = true` (no dock icon)
- [ ] T003 Create folder structure: `LLMStatus/Models/`, `LLMStatus/Services/`, `LLMStatus/Views/`
- [ ] T004 Create minimal `LLMStatusApp.swift` with empty MenuBarExtra (.window style) and static SF Symbol icon

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared models and services that ALL user stories depend on

**CRITICAL**: No user story work can begin until this phase is complete

- [ ] T005 [P] Create `LLMStatus/Models/ServiceProvider.swift` — ServiceProvider struct with id, name, statusURL, apiBaseURL, currentStatus, lastChecked, incidents fields
- [ ] T006 [P] Create `LLMStatus/Models/ServiceStatus.swift` — ServiceStatus enum (operational/degraded/majorOutage/critical/unknown) with color, sfSymbol, and init(fromIndicator:) mapping
- [ ] T007 [P] Create `LLMStatus/Models/Incident.swift` — Incident struct with id, name, impact, status, createdAt, resolvedAt, updates, affectedComponents + IncidentImpact, IncidentStatus, IncidentUpdate types
- [ ] T008 [P] Create `LLMStatus/Models/APIResponses.swift` — StatusResponse and IncidentsResponse DTOs with CodingKeys for snake_case JSON mapping
- [ ] T009 Create `LLMStatus/Services/StatusFetcher.swift` — async functions fetchStatus(baseURL:) → StatusResponse and fetchIncidents(baseURL:) → [Incident] using URLSession + JSONDecoder with snake_case strategy
- [ ] T010 Create `LLMStatusTests/StatusFetcherTests.swift` — Unit tests with mock JSON responses: test parseStatusResponse (all 4 indicators), test parseIncidentsResponse (active + resolved), test malformed JSON returns nil

**Checkpoint**: Foundation ready — models decode Statuspage API, fetcher can retrieve and parse data

---

## Phase 3: User Story 1 — Statut dans la menu bar (Priority: P1) MVP

**Goal**: L'icône de la menu bar reflète le statut agrégé de tous les services LLM (vert/jaune/rouge/gris)

**Independent Test**: Lancer l'app → icône apparaît dans la menu bar. Simuler une réponse JSON avec indicator "major" → icône passe en rouge.

### Tests for User Story 1

- [ ] T011 [P] [US1] Create `LLMStatusTests/StatusMonitorTests.swift` — Test aggregation logic: all operational → green, one degraded → yellow, one major → red, fetch failure → gray. Test polling starts/stops correctly.
- [ ] T012 [P] [US1] Create `LLMStatusTests/ServiceStatusTests.swift` — Test init(fromIndicator:) mapping for all values, test color and sfSymbol properties

### Implementation for User Story 1

- [ ] T013 [US1] Create `LLMStatus/Services/StatusMonitor.swift` — @Observable class with providers array, aggregatedStatus computed property (worst status wins), startPolling(interval:) using Task.sleep loop, stopPolling(), fetchAllStatuses() calling StatusFetcher for each provider
- [ ] T014 [US1] Define default providers in StatusMonitor.init(): Anthropic (https://status.claude.com/api/v2) and OpenAI (https://status.openai.com/api/v2)
- [ ] T015 [US1] Update `LLMStatusApp.swift` — Wire StatusMonitor as @State, pass to MenuBarExtra label (dynamic SF Symbol from aggregatedStatus.sfSymbol), start polling on appear

**Checkpoint**: App shows colored icon in menu bar reflecting real Anthropic/OpenAI status. Clicking does nothing yet.

---

## Phase 4: User Story 2 — Popup de détail (Priority: P2)

**Goal**: Cliquer sur l'icône affiche un popup avec la liste des services, leur statut individuel, et les incidents actifs

**Independent Test**: Cliquer sur l'icône → popup affiche Anthropic et OpenAI avec statut coloré + date du dernier refresh. Si un incident est actif, son titre et lien sont visibles.

### Implementation for User Story 2

- [ ] T016 [P] [US2] Create `LLMStatus/Views/ServiceRowView.swift` — SwiftUI view: status colored circle (SF Symbol), provider name, status text, last checked time. If incident active: incident name + link to status page
- [ ] T017 [P] [US2] Create `LLMStatus/Views/IncidentDetailView.swift` — SwiftUI view: incident title, impact badge (minor/major/critical), status badge, timeline of updates, link to full incident page
- [ ] T018 [US2] Create `LLMStatus/Views/StatusPopoverView.swift` — Main popover: header with "LLM Status" title + last refresh timestamp, List of ServiceRowView for each provider, divider, footer with "Refresh Now" button + "Settings" link + "Quit" button
- [ ] T019 [US2] Wire StatusPopoverView into `LLMStatusApp.swift` MenuBarExtra content, pass StatusMonitor environment, set frame(width: 320)

**Checkpoint**: Clicking menu bar icon shows popover with real service statuses and incident details.

---

## Phase 5: User Story 3 — Notifications macOS (Priority: P2)

**Goal**: Notification macOS native quand un service change de statut (opérationnel → incident), sans doublons

**Independent Test**: Simuler un changement de status (none → major) → notification macOS apparaît. Re-simuler le même incident → pas de notification dupliquée.

### Tests for User Story 3

- [ ] T020 [P] [US3] Create `LLMStatusTests/NotificationManagerTests.swift` — Test shouldNotify logic: new incident → true, same incident already notified → false, incident resolved then new incident → true. Test notification content format.

### Implementation for User Story 3

- [ ] T021 [US3] Create `LLMStatus/Services/NotificationManager.swift` — requestPermission() async, sendIncidentNotification(provider:incident:) with deterministic identifier (providerID-incidentID) for deduplication, track notified incidents in Set<String>
- [ ] T022 [US3] Integrate NotificationManager into StatusMonitor — after each fetchAllStatuses(), compare new incidents vs previous state, call sendIncidentNotification for new/changed incidents only
- [ ] T023 [US3] Request notification permission on first app launch in `LLMStatusApp.swift` .onAppear

**Checkpoint**: App sends macOS notification on new incidents, no duplicates. All 3 user stories work together.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Settings, launch at login, edge cases, final polish

- [ ] T024 [P] Create `LLMStatus/Views/SettingsView.swift` — Refresh interval picker (1/2/5/10 min), launch at login toggle (SMAppService), notifications enabled toggle, app version display
- [ ] T025 [P] Create `LLMStatus/Models/AppSettings.swift` — @Observable class with @AppStorage properties: refreshInterval, launchAtLogin, notificationsEnabled
- [ ] T026 Wire SettingsView into StatusPopoverView footer (sheet or navigation)
- [ ] T027 Integrate AppSettings into StatusMonitor (use refreshInterval for polling) and NotificationManager (check notificationsEnabled)
- [ ] T028 Handle edge cases in StatusFetcher: network timeout (5s), invalid JSON (return .unknown status), HTTP errors (log + return .unknown)
- [ ] T029 Add "Open status page" action on ServiceRowView — open provider statusURL in default browser via NSWorkspace.shared.open()
- [ ] T030 Add app icon (SF Symbol-based or simple custom icon for menu bar)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 completion — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Phase 2 — MVP target
- **US2 (Phase 4)**: Depends on Phase 2 + partial US1 (StatusMonitor must exist)
- **US3 (Phase 5)**: Depends on Phase 2 + partial US1 (StatusMonitor must exist)
- **Polish (Phase 6)**: Depends on US1+US2+US3 completion

### User Story Dependencies

- **US1 (P1)**: Independent after Foundational — creates StatusMonitor (core dependency for US2/US3)
- **US2 (P2)**: Needs StatusMonitor from US1 — but UI is independent
- **US3 (P2)**: Needs StatusMonitor from US1 — integrates notification calls into polling loop

### Within Each User Story

- Tests written and FAIL before implementation
- Models before services
- Services before views
- Core logic before integration

### Parallel Opportunities

- T005, T006, T007, T008 can all run in parallel (different model files)
- T011, T012 can run in parallel (different test files)
- T016, T017 can run in parallel (different view files)
- T024, T025 can run in parallel (different files)

---

## Parallel Example: User Story 1

```bash
# Launch model tests in parallel:
Task: "StatusMonitorTests in LLMStatusTests/StatusMonitorTests.swift"
Task: "ServiceStatusTests in LLMStatusTests/ServiceStatusTests.swift"

# Then implement sequentially:
Task: "StatusMonitor in LLMStatus/Services/StatusMonitor.swift"  # depends on tests
Task: "Wire into LLMStatusApp.swift"                              # depends on StatusMonitor
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T004)
2. Complete Phase 2: Foundational (T005-T010)
3. Complete Phase 3: User Story 1 (T011-T015)
4. **STOP and VALIDATE**: Icon appears, changes color based on real Anthropic/OpenAI status
5. Ship to personal use

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. US1 → Menu bar icon works → **MVP usable!**
3. US2 → Click shows detail popup → More useful
4. US3 → Notifications on incidents → Fully featured
5. Polish → Settings, launch at login → Production ready

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to user story for traceability
- Constitution requires TDD for business logic (parsing, state transitions)
- Commit after each task or logical group
- Zero third-party dependencies — all Foundation/SwiftUI native
- Total: 30 tasks across 6 phases

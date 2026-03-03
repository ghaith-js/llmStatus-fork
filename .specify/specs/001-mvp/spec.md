# Feature Specification: LLM Status MVP

**Feature Branch**: `001-mvp`
**Created**: 2026-03-03
**Status**: Draft
**Input**: Validated idea from /test-idea (llm-status-bar)

## User Scenarios & Testing

### User Story 1 — Voir le statut des services LLM d'un coup d'oeil (Priority: P1)

En tant que développeur, je veux voir dans ma menu bar macOS un indicateur coloré (vert/jaune/rouge) qui reflète l'état actuel des services Anthropic et OpenAI, pour savoir instantanément si mes outils et features LLM fonctionnent normalement.

**Why this priority**: C'est la proposition de valeur core — visibilité instantanée sans friction.

**Independent Test**: Lancer l'app, vérifier que l'icône apparaît dans la menu bar. Simuler un flux RSS avec un incident actif et vérifier que l'icône passe en rouge.

**Acceptance Scenarios**:

1. **Given** l'app est lancée et les services Anthropic/OpenAI sont opérationnels, **When** l'app parse les flux RSS, **Then** l'icône menu bar affiche un indicateur vert.
2. **Given** un incident est déclaré sur status.anthropic.com, **When** l'app rafraîchit le flux RSS, **Then** l'icône passe en jaune (dégradé) ou rouge (down) selon la sévérité.
3. **Given** l'app n'arrive pas à joindre les flux RSS (pas de connexion internet), **When** le refresh échoue, **Then** l'icône affiche un état "inconnu" (gris) sans crash.

---

### User Story 2 — Voir le détail des services dans un popup (Priority: P2)

En tant que développeur, je veux cliquer sur l'icône menu bar pour voir un popup listant chaque service (Anthropic API, Claude Code, OpenAI API) avec son statut individuel et le dernier incident s'il y en a un.

**Why this priority**: L'icône donne le résumé, le popup donne le contexte — les devs veulent savoir QUEL service est impacté.

**Independent Test**: Cliquer sur l'icône, vérifier que le popup liste les services avec leur statut individuel. Vérifier que le dernier incident est affiché si présent.

**Acceptance Scenarios**:

1. **Given** tous les services sont opérationnels, **When** je clique sur l'icône, **Then** je vois la liste des services avec un statut vert pour chacun et la date du dernier refresh.
2. **Given** OpenAI API a un incident actif, **When** je clique sur l'icône, **Then** je vois OpenAI API en rouge avec le titre de l'incident et un lien vers la page status.

---

### User Story 3 — Recevoir une notification macOS quand un service tombe (Priority: P2)

En tant que développeur, je veux recevoir une notification macOS native quand un service LLM passe en incident, pour être prévenu sans avoir à vérifier manuellement.

**Why this priority**: La valeur de l'app est la proactivité — prévenir le dev AVANT qu'il ne rencontre une erreur dans son code.

**Independent Test**: Simuler un changement de statut dans le flux RSS (opérationnel → incident) et vérifier qu'une notification macOS est déclenchée.

**Acceptance Scenarios**:

1. **Given** Anthropic API était opérationnel, **When** un nouvel incident apparaît dans le flux RSS, **Then** une notification macOS est envoyée avec le nom du service et le titre de l'incident.
2. **Given** un incident est déjà connu et notifié, **When** le même incident est encore dans le flux RSS au prochain refresh, **Then** aucune notification dupliquée n'est envoyée.

---

### Edge Cases

- Que se passe-t-il quand le flux RSS est temporairement inaccessible (timeout réseau) ?
- Comment l'app gère-t-elle un format RSS inattendu ou modifié par le provider ?
- Que se passe-t-il si l'app est lancée pour la première fois sans connexion internet ?
- Comment gérer les incidents "resolved" — retour au vert automatique ?

## Requirements

### Functional Requirements

- **FR-001**: L'app DOIT parser les flux RSS/Atom de status.anthropic.com et status.openai.com
- **FR-002**: L'app DOIT afficher un indicateur coloré (vert/jaune/rouge/gris) dans la menu bar macOS
- **FR-003**: L'app DOIT envoyer une notification macOS native lors d'un changement de statut (opérationnel → incident)
- **FR-004**: L'app DOIT afficher un popup avec le détail par service au clic sur l'icône
- **FR-005**: L'app DOIT rafraîchir les flux RSS à intervalle configurable (défaut : 5 minutes)
- **FR-006**: L'app DOIT se lancer au démarrage du Mac (option activable)
- **FR-007**: L'app DOIT éviter les notifications dupliquées pour un même incident

### Key Entities

- **Service** — Un provider LLM monitoré (Anthropic, OpenAI), avec son URL de flux RSS, son statut actuel, et la date du dernier check
- **Incident** — Un événement d'incident parsé du flux RSS, avec titre, sévérité, date, et statut (active/resolved)
- **StatusCheck** — Un résultat de parsing RSS à un instant T, avec timestamp et liste d'incidents trouvés
- **Notification** — Un enregistrement des notifications envoyées pour éviter les doublons

## Success Criteria

- **SC-001**: Le dev voit le statut agrégé de ses services LLM en moins de 1 seconde (un coup d'oeil à la menu bar)
- **SC-002**: La notification macOS arrive dans les 5 minutes suivant la publication d'un incident sur la page status
- **SC-003**: L'app consomme moins de 50 MB de RAM et 0% CPU en idle (léger comme iStat Menus)
- **SC-004**: Zéro faux positif — l'app ne notifie que sur de vrais incidents, pas sur des erreurs de parsing

## Context from Idea Validation

> **Viability Score**: 8.5/10
> **Market**: Sparse — aucun concurrent direct natif macOS pour le status LLM
> **Top Competitors**: Helicone Status, StatusGator, ClaudeMeter/AI Meter
> **Product Type**: Desktop Software (macOS natif)
>
> Full validation report: ~/.claude/output/ideas/llm-status-bar/idea.md

---
project_id: llm-status-bar
product_type: Desktop Software (macOS natif)
status: validated
validated_at: 2026-03-03
viability_score: 8.5/10
verdict: build
---

# LLM Status

**Tagline:** Sache en un coup d'oeil si tes services LLM sont up — et si tes apps ont bien switchés
**Type:** Desktop Software (macOS natif, menu bar)

## Overview

| Aspect | Value |
|--------|-------|
| Revenue Model | Gratuit + donations |
| Target | Développeurs et freelances utilisant des LLM en prod |
| Pricing | Gratuit (donations optionnelles) |
| Build Complexity | Phase 1: Facile / Phase 2: Moyen / Phase 3: Complexe |
| Distribution Complexity | Facile |
| Viability Score | 8.5/10 |

## The Problem

Quand un service LLM (Anthropic, OpenAI) tombe, le workflow dev est perturbé immédiatement (Claude Code inutilisable) et les features SaaS qui dépendent de ces modèles sont aussi down — sans visibilité rapide sur l'état réel des services. Les devs découvrent souvent les pannes en rencontrant des erreurs, pas en étant prévenus.

À plus long terme, les services qui utilisent des LLM en production n'ont aucun outil pour vérifier que leur fallback de modèle fonctionne quand un provider est down.

## Customer Avatar

Dev full-stack, 25-40 ans, utilise Claude Code / Cursor / OpenAI API quotidiennement, ship des SaaS avec des features LLM intégrées, a déjà été impacté par une panne Anthropic/OpenAI sans le savoir immédiatement. Travaille en freelance ou en petite équipe. Préfère les outils légers et natifs plutôt que les dashboards web lourds.

## Vision — 3 Phases

### Phase 1 — MVP (Status Monitor)
- Parser les RSS de status.anthropic.com et status.openai.com
- Indicateur vert/jaune/rouge dans la menu bar macOS
- Notification macOS quand un service passe en incident
- Refresh configurable (temps réel ou toutes les X minutes)

### Phase 2 — Expansion (Multi-Provider + Config)
- Ajouter OpenRouter et autres providers LLM
- Interface de configuration : choisir quels services suivre (usage perso/pro)
- Notifications personnalisables par service
- Distinction services "prod" vs "dev" avec alertes différenciées

### Phase 3 — Plateforme (Intelligent Switching)
- Connecter ses propres services qui utilisent des LLM
- Vérifier que le service du dev a bien switch de modèle quand le provider LLM est down
- Monitoring de fallback automatique
- Base pour un système d'intelligent model switching en fonction de la disponibilité des providers

## Competitor Landscape

| Concurrent | Ce qu'il fait | Pricing |
|------------|---------------|---------|
| Helicone Status | Dashboard web statut LLM (OpenAI, Claude, etc.) | Gratuit |
| StatusGator | Agrégateur 5000+ pages status, alertes | Freemium |
| IsDown | Checker statut temps réel, 20+ intégrations | Free tier |
| ModelStatus.ai | Monitoring Anthropic spécifique | Gratuit |
| Vibe Meter | Tracker dépenses AI menu bar | Free & OSS |
| ClaudeMeter | Usage tracker Claude menu bar | Free (Homebrew) |
| AICostBar | Calculateur coûts LLM | 2.99$ one-time |
| TokenBar | Usage tracker multi-provider | 4.99$ one-time |

**Market Assessment:** Sparse — aucun concurrent direct fait "statut de disponibilité LLM → menu bar macOS native". Marché adjacent validé (10+ apps) mais dominé par free/OSS. Revenus faibles dans la niche.

## Unique Value Proposition

**Phase 1-2:** Le seul widget macOS natif qui agrège le statut de disponibilité de tous les providers LLM en un seul endroit.

**Phase 3:** Le seul outil qui vérifie que VOS services ont bien fait le fallback de modèle quand un provider LLM est down — et qui pose les bases pour de l'intelligent model switching automatique.

## MVP Core Feature (Phase 1)

Parser les flux RSS de status.anthropic.com et status.openai.com, afficher un indicateur coloré dans la menu bar macOS, envoyer une notification native quand un service passe en incident.

## What's NOT in MVP

- Configuration multi-services (phase 2)
- Notifications personnalisables par service (phase 2)
- OpenRouter et providers secondaires (phase 2)
- Connexion aux services du dev (phase 3)
- Détection de fallback de modèle (phase 3)
- Intelligent model switching (phase 3)

## Distribution Strategy

1. **Réseaux sociaux (X/Twitter, LinkedIn)** — Build in public, partager le développement
2. **Product Hunt** — Launch pour la visibilité communauté dev
3. **Mac App Store** — Distribution long-terme et crédibilité
4. **Open source (GitHub)** — Contributions communautaires, visibilité HN

## Challenges & Risks

1. **Problème épisodique** — Les pannes LLM arrivent quelques fois par mois. 95% du temps l'app affiche "tout va bien". Risque que les users oublient l'app.
2. **Monétisation difficile** — Marché dominé par le free/OSS. Donations = revenus marginaux. Business viable seulement si Phase 3 se concrétise.
3. **Alternatives triviales** — Un dev peut suivre @AnthropicStatus sur Twitter ou s'abonner au RSS dans un lecteur. Le gain marginal de l'app menu bar est limité pour la Phase 1.
4. **Phase 3 spéculative** — Le marché de l'intelligent model switching n'existe pas encore. Exécution complexe. Mais first-mover advantage possible.

## Viability Score Breakdown

| Factor | Score | Notes |
|--------|-------|-------|
| Personal fit | 5/5 | Builder = utilisateur #1, dogfooding parfait |
| Build feasibility | 5/5 | Phase 1 MVP = un weekend en SwiftUI |
| Market exists | 3/5 | Adjacent validé mais free/OSS dominant, Phase 3 spéculative |
| Reach | 4/5 | Dev community accessible, bons canaux choisis |
| Differentiation | 4/5 | Phase 1 faible, Phase 3 massive — vision long-terme est le vrai moat |

**Total: 8.5/10** — Build it

---
*Validated: 2026-03-03*

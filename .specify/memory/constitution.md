# LLM Status Constitution

## Core Principles

### I. Core Value — Status Visibility
L'app doit fournir une visibilité instantanée sur la disponibilité des services LLM directement dans la menu bar macOS. Un coup d'oeil suffit : vert = tout va bien, jaune = dégradé, rouge = down. Zéro friction, zéro clic nécessaire pour l'info essentielle.

### II. Target User — Developer-First
Chaque décision est filtrée par : "Est-ce que ça aide un dev qui utilise des LLM en prod ?". L'avatar : dev full-stack 25-40 ans, utilise Claude Code/Cursor/OpenAI API quotidiennement, ship des SaaS avec features LLM. L'app doit être aussi légère et discrète que possible — les devs détestent le bloat.

### III. Build Discipline — Native & Progressive
App 100% native macOS (Swift/SwiftUI). Phase 1 = MVP minimal (JSON API parser + menu bar + notifications). Pas d'over-engineering. Chaque phase s'empile sur la précédente. TDD pour la logique métier (parsing, état des services). Ship fast, iterate based on real usage.

### IV. Revenue Model — Open Source + Donations
Gratuit et open source. Donations optionnelles (GitHub Sponsors / Buy Me a Coffee). Pas de paywall sur les fonctionnalités core. La monétisation n'est pas l'objectif — l'utilité personnelle et la visibilité communautaire le sont. Potentiel freemium uniquement en Phase 3 (intelligent switching).

### V. Differentiation — De Status à Intelligent Switching
Le moat long-terme n'est pas le status monitoring (trivial) mais la vision Phase 3 : connecter ses propres services, vérifier les fallbacks de modèle, et poser les bases d'un intelligent model switching. Protéger cette trajectoire en gardant l'architecture extensible dès Phase 1.

## Market Context

Marché sparse : aucun concurrent direct ne fait "statut de disponibilité LLM → menu bar macOS native". 10+ apps adjacentes (trackers d'usage/coûts) valident la demande. Concurrents web-based (StatusGator, IsDown, Helicone) existent mais aucun n'est natif macOS. Le marché est dominé par le free/OSS — le business model doit en tenir compte. Voir `.specify/memory/validated-idea.md` pour la recherche complète.

## Constraints

- Développeur solo (side-project)
- macOS uniquement (pas de cross-platform pour Phase 1-2)
- Dépendance à l'API JSON Statuspage v2 des providers (status.claude.com, status.openai.com) — si le format change, l'app casse
- Phase 1 MVP doit être shippable en un weekend
- Pas de backend — tout tourne en local sur la machine du dev
- Distribution : GitHub + Mac App Store

## Governance

Cette constitution reflète l'idée validée (score 8.5/10). Tout amendement qui change la proposition de valeur core (status visibility) ou l'audience cible (développeurs) nécessite une re-validation via /test-idea.

**Version**: 1.0.0 | **Ratified**: 2026-03-03 | **Last Amended**: 2026-03-03

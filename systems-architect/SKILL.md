---
name: systems-architect
description: Systems analysis and architecture knowledge base. Use when breaking down a project into modules, designing architecture, evaluating trade-offs, creating technical documentation, or planning development phases. Provides 57 atomic architecture concepts (DDD, C4, Event Storming, ADR, quality attributes) and methodology framework from a systems analysis course.
---

# Systems Architect

Architectural analysis and project decomposition using systems analysis methodology.

## Invocation — Mandatory Steps

When this skill is invoked, the agent MUST:

1. Read `systems-analysis-context.md` — compressed methodology overview
2. Read ALL 57 knowledge files in `knowledge/` — atomic architecture concepts with cross-links
3. Use `related:` fields in knowledge file frontmatter to navigate between concepts

This is a "looking glass" skill: the full knowledge base must be loaded to provide informed architectural analysis. Partial loading leads to incomplete recommendations.

## Knowledge Base (knowledge/)

57 atomic concept files, each 200-500 words, with YAML frontmatter containing:
- `title` — concept name
- `domain` — knowledge domain
- `tags` — classification tags
- `keywords` — search terms (Russian + English)
- `related` — cross-links to other knowledge files
- `source` — lecture reference

### Concept Index

| Category | Files |
|---|---|
| Foundations | system-elements-relations, system-models-extended, problem-space-solution-space, strategy-vs-tactics, local-global-complexity |
| DDD Strategic | business-domain, subdomains, subdomain-evolution, bounded-context, ubiquitous-language, strategic-ddd, core-domain-chart |
| Coupling & Cohesion | coupling-cohesion, types-of-coupling, instability-metric |
| Architecture Styles | layered-architecture, modular-monolith, microkernel-architecture, pipeline-architecture, service-based-architecture, microservices-architecture, event-driven-architecture |
| Quality Attributes | quality-attributes, quality-attribute-scenarios, finding-quality-attributes, fitness-functions, company-lifecycle |
| Patterns | cqrs, event-sourcing, saga-pattern, strangler-fig, change-data-capture |
| Communication | communication-types, event-storming, data-model, database-selection |
| Stakeholders | stakeholder-matrix, requirements-gathering, external-constraints |
| Documentation | adr, architecture-frameworks, architecture-documentation-practices, architecture-checklists, v-model |
| Decomposition | architecture-decomposition, monolith-decomposition-sequence, service-boundary-strategies, refactoring-approaches |
| Anti-patterns | entity-service-antipattern, notification-service-antipattern |
| Advanced | architecture-kata, architecture-selling, architecture-tactics, tactical-forking, team-topologies, wardley-maps, three-stages-architecture |

## Sources (sources/)

15 course lecture files (7-143K each) for deep-dive when knowledge base is insufficient. Always use `offset`/`limit` when reading — never read whole.

| Topic | Source |
|---|---|
| Course context, homework | Предисловие, в котором объясняется контекст курса и домашка |
| Systems, problem/solution space | Урок 1 + 1.1 + 1.2 |
| Requirements, stakeholders | Урок 2 + 2.1 |
| Strategic DDD, bounded contexts | Урок 2.2 |
| Quality attributes | Урок 3 + 3.1 |
| Architectural styles | Урок 3.2 |
| Event Storming, integrations | Урок 4 + 4.1 |
| ADR, fitness functions | Урок 4.2 |
| C4, arc42, checklists | Урок 5 + 5. Послесловие |

## Context File (systems-analysis-context.md)

Compressed methodology reference covering all 11 sections: key concepts, methodology, strategic DDD, frameworks/styles, quality attributes, integrations, stakeholders, ADR, fitness functions, refactoring, checklists.

## Methodology

### Phase 1: Problem Space
- Identify stakeholders and their goals
- Map business processes (domain)
- Define bounded contexts (DDD)
- List quality attributes (scale, latency, security)

### Phase 2: Solution Design
- Choose architectural style (monolith first, split later)
- Decompose into modules (module = bounded context + clear API)
- Define integrations: sync (API) vs async (events), data ownership
- Describe C4 levels: Context -> Container -> Component
- Write ADRs for key decisions

### Phase 3: Planning
- Prioritize modules by business value x technical risk
- Define MVP scope
- Estimate team requirements per phase
- Design PoC to validate core assumptions

## Rules

- Knowledge base first, sources only when needed
- Russian for all documentation
- Every architectural decision -> ADR with rationale
- Prefer simple (monolith -> modular monolith -> microservices)
- Tag open questions explicitly — they become interview topics

## File Structure

```
systems-architect/
  SKILL.md                      # this file
  systems-analysis-context.md   # compressed methodology overview
  knowledge/                    # 57 atomic concept files
    adr.md
    architecture-checklists.md
    ... (57 files)
    wardley-maps.md
  sources/                      # 15 course lecture files
    Предисловие, в котором объясняется контекст курса и домашка.md
    Урок 1.md
    ... (15 files)
    Урок 5. Послесловие.md
```

# ADR-0008: Lightweight Client State Management (No Heavy State Library)

## Status
Accepted — validated, not contradicted, by [GraphUI.md](../GraphUI.md) §10/§11, which builds the full graph view-state model (reference-counted visibility, per-node pagination cursors, a fourth state category for the Presentation Type Registry cache) entirely within the three mechanisms decided below, with no heavy state library introduced despite substantially more state shape than existed when this record was first written

## Context
The graph UI has multiple interdependent components (canvas, mini-map, breadcrumb, filter panel, detail panel) that need to share view state (current center node, expanded/collapsed set, active filters, selection). `CLAUDE.md` §Core Principles explicitly says: "prefer simple architecture that scales over complicated architecture that appears enterprise" and warns against unnecessary complexity. The LWC framework has no built-in global state container equivalent to Redux/Vuex.

## Decision
Use three explicitly separated, purpose-fit mechanisms (Architecture §10) instead of adopting a general-purpose state-management library:
1. A small module-scoped reactive JS store for ephemeral UI state, owned by the shell component.
2. `sessionStorage` for session-lifetime state (recent searches, last-viewed graph).
3. Apex `@wire`/imperative calls plus Platform-Event-driven push (`empApi`) for server-authoritative state.

Data flows top-down from the shell via properties; children emit events upward; Lightning Message Service handles pub/sub between non-parent/child siblings (e.g., shell → mini-map, shell → breadcrumb).

## Consequences
- **Positive**: no third-party state library to vet for Security Review, vendor, or keep updated — directly serves "prefer native platform capabilities" and "avoid unnecessary complexity."
- **Positive**: state ownership is unambiguous — a developer asking "where does X live" has exactly three answers, not an open-ended set of contexts/stores/slices to search.
- **Negative**: as the component tree grows, purely event-up/property-down flow can become verbose if nesting gets deep — mitigated by keeping the component tree shallow (Architecture §9's shell owns nearly all children directly) and revisited only if a concrete pain point emerges in practice (Roadmap Phase 2 explicitly validates this decision against a second real consumer before the rest of the UI shell is built on top of it). The full graph view-state model ([GraphUI.md](../GraphUI.md) §11) is that validation, arriving with materially more state shape (per-node ancestor/revealed sets, pagination cursors, a working-set size) than was known when this ADR was first written, and the module-scoped-store approach still holds without modification — a positive signal this decision was not merely adequate for a smaller problem than the one that eventually arrived.
- **Negative**: no framework-provided time-travel debugging/dev-tools that a library like Redux would offer — accepted; `OI_LoggerService` correlation IDs (Architecture §13) provide the debugging trail this product actually needs (server-side action tracing), which matters more here than client-state time-travel.

## Alternatives Considered
- **A general JS state-management library (Redux-style) bundled as a static resource** — rejected: adds a third-party dependency requiring Security Review vetting (ADR-related concern also raised in CodingStandards §11) for a problem three native/simple mechanisms already solve at this UI's actual complexity; revisit only if the component tree grows far beyond the current planned shell.
- **Everything in Apex, re-fetched on every interaction** — rejected: violates "never load an entire org" / minimize server round-trips (Architecture §1, §17); ephemeral UI interactions like pan/zoom/expand must be instant and client-local.

## Related
Architecture.md §9, §10; Roadmap.md Phase 2; [GraphUI.md](../GraphUI.md) §10, §11, §13.

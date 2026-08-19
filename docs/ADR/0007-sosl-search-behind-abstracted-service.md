# ADR-0007: SOSL-Based Search Behind an Abstracted Search Service

## Status
Accepted — the abstraction seam described below is given a concrete mechanism by [ADR-0017](0017-search-provider-abstraction-record-search-outside-graph.md) (the `OI_ISearchProvider` abstraction) and fully elaborated in [SearchEngine.md](../SearchEngine.md); nothing in this record's Decision is contradicted, only made precise

## Context
Users need fast typeahead search across potentially tens of thousands of graph nodes (objects, fields, classes, flows, etc.), plus exact "jump to" lookups. `CLAUDE.md` mandates preferring native platform capabilities over custom frameworks and choosing "the lightest solution capable of solving the problem." Salesforce's built-in SOSL search is native, requires no custom indexing infrastructure, and is exactly this kind of typeahead-search fit for record data stored in searchable custom objects.

## Decision
Implement `OI_SearchService` as the sole seam for search, backed in v1 entirely by SOSL (`FIND`) for relevance-ranked typeahead and SOQL exact-match for structured "jump to" lookups (Architecture §8). No callers (Controllers, LWCs) talk to SOSL directly — only `OI_SearchService` does — so the backing mechanism can be swapped later without touching anything above it.

## Consequences
- **Positive**: zero custom indexing code, zero additional infrastructure, fully native — satisfies "prefer native platform capabilities" directly and is the lightest solution that meets the stated requirement.
- **Positive**: the abstraction seam means that *if* real-world usage at large-org scale reveals SOSL's characteristics (indexing latency, result-set ranking behavior, or query-length/complexity limits) are insufficient, the fix is localized to `OI_SearchService`'s internals — no Controller, DTO, or LWC changes required. [ADR-0017](0017-search-provider-abstraction-record-search-outside-graph.md) makes this precise: the fix is a new `OI_ISearchProvider` implementation ([SearchEngine.md §5, §26](../SearchEngine.md#5-search-provider-abstraction)).
- **Negative**: SOSL's relevance ranking is Salesforce-controlled and not deeply customizable; if search quality tuning becomes a real customer complaint, that's a real limitation of this choice — tracked as Backlog item SR-5/SR-6, deliberately not solved speculatively now.
- **Negative**: SOSL operates over indexed searchable objects, so the *entire* graph must actually be persisted as `OI_Graph_Node__c` rows (already true per ADR-0001/0002) for search to see it — no incremental issue here since persistence is already the design, but worth noting as a dependency.

## Alternatives Considered
- **Custom inverted index (rolled by hand in Apex/custom objects)** — rejected: directly contradicts "prefer native platform capabilities before introducing custom frameworks" and adds significant maintenance surface for a problem SOSL already solves adequately at anticipated scale.
- **External search index (e.g., a hosted search service via Named Credential)** — rejected for v1: introduces an external dependency, cost, and Security-Review surface (outbound integration, data leaving the org) with no demonstrated need yet; explicitly deferred as a *possible* future evolution behind the same `OI_SearchService` seam, not built speculatively (`CLAUDE.md` — "never invent missing business requirements").

## Related
Architecture.md §8; [SearchEngine.md](../SearchEngine.md) (full elaboration); [GraphUI.md](../GraphUI.md) §8 (the UI-side half of the search-to-graph handoff); ADR-0017; ADR-0018; Backlog.md Epic: Search (SR-6); Roadmap.md Post-GA.

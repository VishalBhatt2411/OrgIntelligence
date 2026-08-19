# ADR-0010: Three-Layer Caching Strategy with Neighborhood-Scoped Invalidation

## Status
Accepted

## Context
Graph browsing (pan/zoom/expand) and search must feel instant, but the underlying data (graph fragments, impact-analysis results) is expensive to (re)compute or (re)fetch from durable storage, and the platform must "never load an entire org" or hit storage/API limits carelessly (Architecture §1, §17). A single caching mechanism doesn't fit every need here: some state must survive cache eviction (it's the source of truth), some is cheap to keep hot, and some is purely a same-session optimization.

## Decision
Three explicit cache layers, each with a distinct purpose and invalidation trigger (Architecture §11):
- **L1** — Platform Cache (Org partition), hot graph-fragment/search results, TTL + targeted eviction.
- **L2** — Durable Custom Object snapshot (`OI_Graph_Node__c`/`OI_Graph_Edge__c`), the actual source of truth, superseded only by the next scan touching a given node.
- **L3** — In-memory client-side cache within the current LWC session, avoiding redundant Apex round-trips during a single navigation session.

Critically, invalidation is **neighborhood-scoped**: when the Metadata Scanner's checksum diffing (ADR-0009) identifies exactly which nodes changed, only those nodes' cached fragments (and their immediate cached neighbors) are evicted from L1 — not a global cache flush.

## Consequences
- **Positive**: a scan touching a small fraction of the org's metadata doesn't invalidate cached data for the rest of the graph — most users' navigation stays warm across routine rescans, which is exactly what makes incremental scanning (ADR-0009) pay off end-to-end rather than just shifting cost from "scan time" to "everyone's next page load."
- **Positive**: L2 being a durable, independent-of-cache source of truth means a Platform Cache eviction (org cache is not guaranteed permanent) never causes data loss — only a cache-miss round-trip to L2, not a re-scan.
- **Negative**: three layers means three places a staleness bug could theoretically hide — mitigated by the strict rule that L1/L3 are always disposable derivations of L2, never independently authoritative, and by keying L1/L3 identically (`hash(nodeKey + hopDepth + filterSet)`) so their invalidation logic is symmetric and easy to reason about.
- **Negative**: neighborhood-scoped invalidation logic is more complex than "flush everything on every scan" — accepted because the simpler alternative would defeat the purpose of incremental scanning (ADR-0009) by making every scan, however small, feel like a full cold-cache event to every user.

## Alternatives Considered
- **Platform Cache only, no durable snapshot** — rejected: Platform Cache is not guaranteed durable/permanent and re-deriving the graph from Tooling/Metadata API on every eviction would reintroduce the exact API-budget pressure the incremental-scan strategy is meant to relieve.
- **Global cache flush on every scan** — rejected: cheapest to implement, but directly undermines the value of incremental scanning (ADR-0009) — every rescan, even a no-op one, would cold-start every user's next graph view.

## Related
Architecture.md §11; ADR-0009; DataModel.md §2.5.

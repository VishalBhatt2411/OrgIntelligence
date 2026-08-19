# ADR-0009: Incremental Metadata Scanning via Checksum Diffing

## Status
Accepted — the Decision text below ("the scanner compares the newly-fetched entity's checksum against the stored value") is **corrected by [ADR-0015](0015-discovery-model-graph-blind-scanner.md) / [MetadataScanner.md](../MetadataScanner.md) §8**: the Scanner cannot compare against a *stored* (graph) value, since it must not know graph state exists. The Scanner only computes the checksum; the comparison happens in `OI_GraphBuilder`, downstream of the Mutation Generator. The core decision — checksums, not just modstamps, drive change detection — stands unchanged.

## Context
Large orgs have large metadata surfaces; a full rescan touching every object/field/class/flow/etc. on every run is expensive in Tooling/Metadata API calls (which are a shared, limited daily resource in the customer's org — Architecture §17) and in Apex CPU/heap. Most scans, in practice, occur when only a small fraction of metadata has actually changed since the last run.

## Decision
Compute a normalized-content checksum per scanned entity (`OI_Graph_Node__c.Checksum__c`) during each scan; the scanner compares the newly-fetched entity's checksum against the stored value and skips graph/cache updates entirely for unchanged entities. Full rescans remain available and are explicitly opt-in, surfaced to the admin as the more expensive choice (Architecture §6, Roadmap Phase 3).

## Consequences
- **Positive**: routine rescans become proportional to actual org change volume, not org size — directly enables both the API-budget constraint (Architecture §17) and the neighborhood-scoped cache invalidation strategy (ADR-0010), since the scanner now knows precisely which nodes changed.
- **Positive**: this is what makes frequent, low-cost rescanning viable at all for large orgs — without it, "just rescan more often" would be prohibitively expensive and self-imposed API budgets would starve normal usage.
- **Negative**: checksum computation adds a small amount of work per entity even when nothing changed — accepted, since it's vastly cheaper than the graph-write/cache-invalidation work it avoids.
- **Negative**: incremental scanning can miss changes if the checksum's normalized representation doesn't capture some meaningful attribute change — mitigated by defining the checksum over the full normalized DTO (all attributes the scanner extracts), not a partial/summary hash, and by keeping full rescan available as a correctness fallback.

## Alternatives Considered
- **Always full rescan** — rejected: doesn't scale to large orgs within realistic API-call budgets and CPU time, and would make "rescan on every deploy" (a natural CI integration use case per API.md §3) impractical.
- **Rely solely on `SystemModstamp`/`LastModifiedDate`** — considered as a cheaper alternative to content checksums, but rejected as the sole signal: not all metadata types expose a reliable last-modified timestamp via Tooling/Metadata/Describe API consistently, whereas a content checksum works uniformly across every scanner regardless of what timestamp fields that metadata type happens to expose. (Where available, modstamp comparison is still used as a cheap first-pass filter before checksum computation, as a performance optimization — not a replacement for it.)

## Related
Architecture.md §6, §11, §17; ADR-0010; ADR-0015; DataModel.md §2.3, §2.4; [MetadataScanner.md](../MetadataScanner.md) §8.

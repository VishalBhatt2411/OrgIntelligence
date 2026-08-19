# ADR-0002: Hybrid Custom Object + Big Object Graph Persistence

## Status
Accepted — the mechanics in the Decision below ("upserted by external-ID key, holding only the latest known snapshot") are **elaborated by [ADR-0014](0014-immutable-node-edge-versioning.md)**: rows are inserted as new immutable versions rather than upserted in place, and "current state" now means the `Is_Current__c = true` subset of a table that also transiently holds recent non-current versions pending archival. The Custom-Object-vs-Big-Object split itself, and the reasoning below for why, stand unchanged.

## Context
The graph (ADR-0001) needs durable storage. Large subscriber orgs can produce tens of thousands of nodes and a larger multiple of edges, and that volume grows over time as scans accumulate history. Storage must stay within the customer's org storage limits — a hard AppExchange citizenship concern — while still serving interactive graph browsing with acceptable latency.

## Decision
Use a hybrid model:
- **Current-state graph** (`OI_Graph_Node__c`, `OI_Graph_Edge__c`) as standard Custom Objects, upserted by external-ID key, holding only the *latest known* snapshot.
- **Superseded/historical edges** roll off to `OI_Graph_Edge_Archive__b`, a Big Object, once no longer part of the current graph.

Standard Custom Objects are used for the current state because interactive browsing needs synchronous SOQL with indexed lookups and immediate consistency after a scan; Big Objects are used for history because that data is read rarely (occasional "show history" views, roadmap item), tolerates async/eventually-consistent query, and must not count against the transactional storage a customer feels day-to-day.

## Consequences
- **Positive**: the interactive path (current graph) stays fast and small; historical growth is absorbed by Big Object storage, which has fundamentally different (much larger, async-query) capacity characteristics.
- **Positive**: this is a purely additive pattern — nothing about the current-graph query path changes as history accumulates.
- **Negative**: two storage mechanisms means two code paths in the Repository layer (`OI_GraphRepository` writes both) and Big Objects have real constraints (no standard DML, index fields must be declared upfront, async query only) that the archival job must respect.
- **Negative**: "current graph" and "archive" can briefly diverge during the archival job's run; acceptable since archive reads are not on any interactive path.

## Alternatives Considered
- **Custom Objects only, forever** — rejected: unbounded growth against transactional storage limits is exactly the kind of AppExchange Security/Quality Review and customer-trust risk the platform must avoid (Architecture §17).
- **Big Objects for everything, including current state** — rejected: Big Objects don't support standard indexed SOQL the interactive graph-browsing UI needs (no secondary index beyond declared index fields, no synchronous consistency guarantee immediately after write), which would make pan/expand/search feel slow or stale.
- **External storage (e.g., a dedicated graph database via callout)** — rejected outright by the "native Salesforce stack only" constraint in `CLAUDE.md` §Technical Stack for v1.

## Related
Architecture.md §5, §17; DataModel.md §2.3, §2.4, §3; [ADR-0012](0012-graph-repository-storage-gateway.md) (formalizes the Repository/Storage-Provider access pattern this ADR assumed but didn't specify); [ADR-0014](0014-immutable-node-edge-versioning.md) (changes what "current state" vs. "history" means at the row level — this ADR's Custom-Object-vs-Big-Object split stands, now applied to versions rather than single rows per key).

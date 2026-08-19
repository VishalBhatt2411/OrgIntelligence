# ADR-0006: Apex-Boundary Security Model for Application-Internal Data

## Status
Accepted

## Context
`CLAUDE.md` requires respecting CRUD/FLS/sharing and never bypassing security without explicit justification. The platform's own objects (`OI_Graph_Node__c`, `OI_Graph_Edge__c`, `OI_Log__c`, `OI_Scan_Run__c`, etc.) are application-internal — they cache metadata *about* the org for the app's own use, and no end user is meant to query them directly via a list view, report, or arbitrary SOQL. This is a fundamentally different data-ownership shape than customer business records (Accounts, custom business objects) that CRUD/FLS/sharing were designed to protect between business users.

## Decision
Gate access to `OI_*__c` application-internal objects at the **Apex API boundary** via Custom Permissions (`OI_View_Graph`, `OI_Run_Scan`, `OI_Manage_Settings`, `OI_View_Logs`), rather than by building a record-ownership/sharing model for them. Read paths exposed to the UI run `with sharing` and additionally require the relevant Custom Permission; scan-writer paths that upsert graph data run `without sharing` (justified inline per CodingStandards §8) since these records have no meaningful owner-based sharing semantics — every node/edge represents org metadata, not a business transaction belonging to one user.

Data reachable *through* the graph that actually is customer business data (e.g., if a future feature surfaced field-level values, not just field metadata) remains fully subject to standard CRUD/FLS/sharing via `WITH USER_MODE` — this ADR concerns only the platform's own cache/config objects, not customer business data. **Record Search** ([SearchEngine.md §12, §18](../SearchEngine.md#12-record-search), [ADR-0017](0017-search-provider-abstraction-record-search-outside-graph.md)) is the concrete instance of exactly this carve-out: it queries genuine customer business records, not application-internal objects, and is explicitly governed by full CRUD/FLS/sharing plus a separate Custom Permission (`OI_Search_Records`) — never by this ADR's Apex-boundary model.

## Consequences
- **Positive**: avoids building and maintaining a bespoke sharing model (sharing rules, manual share records, or a public/private OWD choice) for data where record-level ownership doesn't map to anything meaningful — the "owner" of a graph node is the scan process, not a business user.
- **Positive**: access control is centralized and auditable in one place (`OI_SecurityService` + Custom Permission checks at every Controller/REST entry point), rather than spread across sharing rules, OWD settings, and Apex — simpler to reason about and to review.
- **Negative**: `without sharing` usage requires discipline (every instance documented, per CodingStandards §8) since it is a real, if narrow, security-relevant deviation from the platform default — mitigated by scoping it strictly to the graph/cache writer paths and requiring a comment justifying each occurrence.
- **Negative**: if a future feature needs different visibility for different users over the *same* graph data (e.g., showing different subsets of the org graph to different business units), this model would need to evolve — deferred until a concrete requirement emerges (not speculated on now, per `CLAUDE.md` "never invent missing business requirements").

## Alternatives Considered
- **Private OWD + Apex-managed sharing for `OI_Graph_Node__c`/`OI_Graph_Edge__c`** — rejected for v1: building and maintaining share-record logic for potentially millions of rows (one graph node/edge per org metadata component) adds real DML/storage overhead for a data set that doesn't have a natural per-record owner in the business sense; Custom-Permission gating achieves the actual goal (only authorized admins/architects see graph data) with far less mechanism.
- **Public Read/Write OWD with no gating** — rejected: violates `CLAUDE.md` §Security ("never expose unauthorized metadata").

## Related
Architecture.md §14; CodingStandards.md §8; DataModel.md §6; [SearchEngine.md](../SearchEngine.md) §12, §18; ADR-0017.

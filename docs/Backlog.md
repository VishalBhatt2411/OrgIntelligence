# Backlog — Salesforce Org Intelligence Platform

Status: Draft v1

Epics map 1:1 to the service boundaries in [Architecture.md §4](Architecture.md#4-service-boundaries). Items are scoped to *what* is needed, not *how* — no implementation detail, per project convention. Priority: **P0** (blocks the Roadmap phase noted), **P1** (needed before GA, not phase-blocking), **P2** (post-GA candidate). This backlog is a planning artifact, not a commitment — re-prioritize freely as pilot feedback arrives.

---

## Epic: Foundation & Cross-Cutting (Roadmap Phase 0)

| # | Item | Priority |
|---|---|---|
| F-1 | `OI_ApplicationException` hierarchy + Controller-boundary translation to `AuraHandledException` | P0 |
| F-2 | `OI_LoggerService` + `OI_Log_Event__e` async write path + `OI_Log__c` | P0 |
| F-3 | `OI_SecurityService` (Custom Permission checks, WITH USER_MODE helper patterns) | P0 |
| F-4 | `OI_SettingsService` reading `OI_Settings__mdt` / `OI_Metadata_Type_Config__mdt` | P0 |
| F-5 | Permission Sets (`OI_Viewer`, `OI_Power_User`, `OI_Administrator`) + Custom Permissions | P0 |
| F-6 | CI pipeline: scratch org create → deploy → Apex/Jest tests → destroy | P0 |
| F-7 | Log retention batch job (`OI_LogRetentionBatch`) | P1 |
| F-8 | `OI_InstallHandler` (seed defaults, no auto-scan on install) | P1 |

## Epic: Metadata Scanner (Roadmap Phase 1 & 3)

Full spec: [MetadataScanner.md](MetadataScanner.md). Discovery Model production (Scanner) and Mutation Generation are separate, sequenced items below — the Scanner has zero Graph Engine dependency and can be built/tested in complete isolation before the Mutation Generator exists ([ADR-0015](ADR/0015-discovery-model-graph-blind-scanner.md)).

| # | Item | Priority |
|---|---|---|
| MS-0 | Discovery Model shapes: `OI_DiscoveryBatch`, `OI_DiscoveredComponent`, `OI_DiscoveredRelationship` — Salesforce vocabulary only, zero Graph Engine reference (MetadataScanner.md §5) | P0 |
| MS-1 | `OI_IMetadataScanner` interface (`scan(context) -> OI_DiscoveryBatch`) + `OI_ScanOrchestratorQueueable` chaining/failure isolation | P0 |
| MS-2 | `OI_ToolingApiAdapter`, `OI_DescribeApiAdapter` — **status corrected 2026-08-19: NOT built.** A source audit found no adapter class, Named Credential, or Remote Site Setting in the package. Every scanner shipped so far (Object, Field, ApexClass, ApexTrigger, Flow, PermissionSet) deliberately uses Describe or plain SOQL instead, which is why this went unnoticed. Tracked as DE-15 in the Cross-Metadata Dependency Scanners epic, since that is where it now blocks work | P0 — not started |
| MS-3 | Scanners: Object, Field, ApexClass — producing Discovery Batches only, no mutation-shaped output | P0 |
| MS-4 | `OI_Scan_Run__c` / `OI_Scan_Task__c` status tracking (including `Is_Full_Snapshot__c`, `Last_Successful_Watermark__c`) + `OI_ScanProgress__e` | P0 |
| MS-4a | `OI_MutationGenerator`: deterministic `componentKind → typeKey` mapping, `nodeKey`/`edgeKey` derivation, checksum/attribute pass-through, calling `OI_GraphEngine.ingest()` only (MetadataScanner.md §15, [ADR-0015](ADR/0015-discovery-model-graph-blind-scanner.md)) — depends on GE-4a existing | P0 |
| MS-4b | `OI_MutationGenerator` retire-detection: read-only, paginated query against `OI_GraphEngine` (backed by `OI_GraphRepository.getCurrentKeysByType`, [GraphRepository.md §2, §9](GraphRepository.md#2-graphrepository-interface)) for current Active keys of a `typeKey`, diffed against a full-scan's observed set (MetadataScanner.md §15) — full scans only, gated on `Is_Full_Snapshot__c = true`; depends on GE-2a | P0 |
| MS-5 | API-level delta fetching (watermark-based, per §8) as the Scanner's own incremental mechanism — distinct from, and upstream of, `OI_GraphBuilder`'s checksum-based content-diff decision (which already existed, unchanged, in GraphEngine.md §7) | P0 (Phase 3) |
| MS-6 | Scanners: Flow, Trigger, ValidationRule | P0 (Phase 3) |
| MS-7 | Scanners: PermissionSet, Profile | P0 (Phase 3) |
| MS-8 | Scanners: LWC, AuraComponent | P1 |
| MS-9 | Scanners: NamedCredential, ExternalService, Package | P1 |
| MS-10 | Scanners: Dashboard, Report | P1 |
| MS-11 | Self-imposed daily API call budget + pause/resume | P1 |
| MS-12 | `OI_MetadataApiAdapter` (for metadata not reachable via Tooling/Describe) | P1 |
| MS-13 | Admin-configurable scan scope (include/exclude namespaces or types) | P2 |
| MS-14 | Per-type cadence (`Min_Rescan_Interval_Minutes__c`) honored by scheduled full-org runs (MetadataScanner.md §13) | P1 |
| MS-15 | Parallel scan chains across metadata types, bounded by a configurable concurrency ceiling (MetadataScanner.md §10) | P2 |

## Epic: Graph Engine (Roadmap Phase 2)

Full spec: [GraphEngine.md](GraphEngine.md); Repository/Storage layer full spec: [GraphRepository.md](GraphRepository.md).

| # | Item | Priority |
|---|---|---|
| GE-0 | `OI_Node_Type_Descriptor__mdt` / `OI_Edge_Type_Descriptor__mdt` Domain Type Registry — prerequisite for every scanner and for the rendering registry ([ADR-0011](ADR/0011-generic-node-edge-typing-via-domain-registry.md)) | P0 |
| GE-1 | Domain model: `OI_Node`, `OI_Edge` as immutable value objects (generic `typeKey`, not an enum; no setters — GraphEngine.md §2–§3, [ADR-0014](ADR/0014-immutable-node-edge-versioning.md)) | P0 |
| GE-3 | `OI_NodeSelector` / `OI_EdgeSelector` (bulk key-set reads, always scoped `Is_Current__c = true`, including the paginated `selectCurrentKeysByType` projection retire-detection needs) — now a **dependency of GE-2a**, not a peer built afterward for Traversal's benefit alone ([GraphRepository.md §12](GraphRepository.md#12-query-strategy--selector-delegation)) | P0 |
| GE-2a | `OI_GraphRepository` + Storage Provider interface (`OI_CustomObjectStorageProvider`, `OI_BigObjectStorageProvider`, `OI_PlatformCacheStorageProvider`) — five operations including the atomic `commitVersion` (insert + supersede-flip in one transaction) and the paginated `getCurrentKeysByType`; delegates all Custom Object reads to GE-3's Selectors rather than querying inline. Built *before* the Builder, since the Builder cannot function without it ([ADR-0012](ADR/0012-graph-repository-storage-gateway.md), [ADR-0016](ADR/0016-repository-atomic-commit-and-optimistic-concurrency.md), full spec [GraphRepository.md](GraphRepository.md)) | P0 |
| GE-2c | Optimistic-concurrency conflict handling in `OI_GraphBuilder`: catch `OI_ConcurrencyException` from `commitVersion`, re-read current state, retry once ([GraphRepository.md §15](GraphRepository.md#15-concurrency-handling), [ADR-0016](ADR/0016-repository-atomic-commit-and-optimistic-concurrency.md)) — depends on GE-2a | P0 |
| GE-2b | `OI_GraphBuilder`: generic Mutation contract (`UpsertNode`/`RetireNode`/`UpsertEdge`/`RetireEdge`) + the three-way versioning decision (new version / liveness touch / no-op), calling `OI_GraphRepository` exclusively — never touches storage itself (GraphEngine.md §7) | P0 |
| GE-4 | `OI_GraphTraversal`: expand (bounded/paginated), filter — enforcing both hop-depth and node-count ceilings (GraphEngine.md §12) | P0 |
| GE-4a | `OI_GraphEngine` facade — composes GE-2a/2b/4 (and later GE-8's `OI_GraphCache`) behind a single public entry point; contains no logic of its own ([ADR-0013](ADR/0013-graphengine-facade.md), GraphEngine.md §1.1) | P0 |
| GE-5 | `OI_GraphController.getGraphFragment` / `getNodeDetail` — calling `OI_GraphEngine` only | P0 |
| GE-6 | Lifecycle state machine (Discovered/Active/Stale/SoftDeleted) as new versions, not flag mutations + grace-period cleanup | P1 |
| GE-7 | Big Object archival (`OI_Graph_Node_Archive__b` **and** `OI_Graph_Edge_Archive__b` — nodes now version too) + archival job covering both purged entities and aged-out non-current versions | P1 (Phase 5) |
| GE-8 | `OI_GraphCache`: neighborhood-scoped cache invalidation on scan delta, policy only — reads/writes Platform Cache through `OI_GraphRepository`'s provider, never directly | P0 (Phase 3, depends on MS-5) |

## Epic: Dependency Engine (Roadmap Phase 4) — DE-0 through DE-6 implemented

| # | Item | Priority |
|---|---|---|
| DE-0 | `OI_ApexClassScanner` REFERENCES-edge extraction (regex/tokenizing heuristic against `ApexClass.Body`, graceful degradation without Author Apex access) — the minimum-viable data source DE-1+ needs to have anything real to traverse; Flow/Trigger/Permission dependency edges remain out of scope (MS-6/MS-7) | P0 — done |
| DE-1 | Forward traversal (depth-bounded) — `OI_GraphTraversal.traverseDirectional` + `OI_GraphEngine.getImpactSubgraph`, `OI_DependencyEngineService.getImpact` | P0 — done |
| DE-2 | Reverse traversal (depth-bounded) | P0 — done |
| DE-3 | Cycle detection (DFS + visited-set) | P0 — done |
| DE-4 | `OI_Impact_Analysis_Cache__c` read/write + TTL — `OI_ImpactCacheRepository`, reusing `Cache_TTL_Minutes__c`; new dedicated `Max_Impact_Depth__c`/`Max_Impact_Traversal_Node_Count__c` on `OI_Settings__mdt` | P0 — done |
| DE-5 | `OI_DependencyController.getImpact` — gated by the existing `OI_View_Graph` permission, no new permission introduced | P0 — done |
| DE-6 | Impact result dual-rendering (graph + flat list) in `oiNodeDetailPanel`, plus "Highlight on Graph" merging into `graphViewState.js`'s existing `applyExpand` | P0 — done |
| DE-7 | Impact-cache invalidation tied to scan deltas touching involved nodes — mechanism built (`OI_DependencyEngineService.invalidateForScanDelta`, `OI_ImpactCacheRepository.evictByRootNodeKeys`), **not yet wired automatically** into `OI_ScanOrchestratorQueueable`/`OI_MutationGenerator` — a small, named follow-up | P1 |

## Epic: Cross-Metadata Dependency Scanners (new, 2026-08-19 — closes the "Impact Analysis is Apex-only" gap)

**Why this epic exists:** a 2026-08-19 code audit confirmed DE-0 through DE-6 are genuinely implemented (real BFS traversal, real DFS cycle detection, real controller/LWC wiring, real passing tests against fixture data — not stubbed). But the *only* edge type the Dependency Engine can traverse is Apex-class-to-Apex-class `REFERENCES` (hardcoded allow-list in `OI_DependencyEngineService.cls:20-25`). There are zero dependency edges for Flow, Trigger, Validation Rule, Permission Set, or Report — so an impact query against a field, object, or Flow correctly returns "no impact" today, which reads identically to "the engine doesn't work" even though it does for the one metadata type it covers. This epic closes that gap. Sequenced after the Graph Canvas Layout Quality epic (UI-13..16) per explicit user priority (Canvas → Impact → AI), and builds on the scanners already named but not yet built in MS-6/MS-7/MS-9/MS-10.

| # | Item | Priority |
|---|---|---|
| DE-8 | Flow dependency scanner — `OI_FlowScanner`, **partially done 2026-08-19**. Delivers the exact record-triggered-Flow → Object `EXECUTES_ON` edge via `FlowDefinitionView` (a standard Apex-queryable view, no callout). **Still missing, and blocked on MS-2:** everything inside a Flow — the fields it reads/updates, the Apex it invokes, the sub-flows it calls. Those live in the Flow metadata definition, reachable only via Tooling/Metadata API | P0 — partial |
| DE-9 | Trigger dependency scanner — `OI_ApexTriggerScanner`, done 2026-08-19. Emits two edge kinds: `EXECUTES_ON` (trigger → the object it fires on) and `REFERENCES` (trigger → Apex classes it calls). **`EXECUTES_ON` is the platform's first EXACT dependency edge** — a trigger's target object is declared in source, not inferred, unlike every regex-heuristic `REFERENCES` edge. Reuses `OI_ObjectScopeFilter` so an edge is never emitted toward an object `OI_ObjectScanner` excludes (Platform Events etc.), preventing dangling edges | P0 — done |
| DE-10 | Validation Rule dependency scanner — edges for Validation Rule → Field references (extends MS-6). **Hard-blocked on MS-2**: `ValidationRule` has no Apex-queryable standard-object equivalent, so unlike DE-8/DE-9/DE-11 there is no partial delivery possible without the Tooling API adapter | P0 — blocked |
| DE-11 | Permission Set dependency scanner — `OI_PermissionSetScanner`, done 2026-08-19. Emits exact `GRANTS_ACCESS_TO` edges to Objects (via `ObjectPermissions`) and Apex classes (via `SetupEntityAccess`), all callout-free. Answers a question no other scanner can: *"who loses access if I delete this?"* Excludes profile-owned permission sets (Profiles need their own componentKind, MS-7). **Field-level grants deliberately excluded** — `FieldPermissions` is the highest-cardinality table in the domain and needs Batch Apex chunking to query safely; named follow-up, not silently dropped | P1 — done (object + Apex class grants) |
| DE-12 | Report dependency scanner — edges for Report → Field/Object usage (extends MS-10, supersedes PG-4) | P1 |
| DE-13 | Extend `OI_DependencyEngineService`'s edge-type allow-list to cover every new dependency edge type — done 2026-08-19 for `SalesforceMetadata.EXECUTES_ON` and `SalesforceMetadata.GRANTS_ACCESS_TO`. The allow-list is documented as the single switch that brings a scanner's edge type into Impact Analysis (traversal itself was already generic over edge type). Re-open when DE-10/DE-12 land | P0 — done for DE-8/9/11; reopens per scanner |
| DE-14 | `oiNodeDetailPanel` impact view groups/labels impact rows by metadata type — done 2026-08-19. Rows now resolve their type through the Presentation Registry (no raw `SalesforceMetadata.*` keys shown to users), and a per-type breakdown ("2 Apex Classes, 1 Apex Trigger, 1 Permission Set") leads the section, suppressed when only one type is present. Matters because the mixed kinds now differ in *consequence*: an Apex class means code may break, a permission set means someone loses access | P0 — done |
| DE-15 | **`OI_ToolingApiAdapter` (= MS-2) genuinely does not exist** — no adapter, Named Credential, or Remote Site Setting anywhere in the package, despite MS-2 being listed P0 in the Metadata Scanner epic. Discovered 2026-08-19 while scoping DE-8/DE-10. This is the single blocker for the remaining dependency coverage (Flow internals, Validation Rules, Report field usage) and carries real AppExchange Security Review weight (first external-callout surface in the package). Sized and sequenced as its own item rather than being smuggled into a scanner ticket | P0 |

## Epic: Search (Roadmap Phase 3)

Full spec: [SearchEngine.md](SearchEngine.md).

| # | Item | Priority |
|---|---|---|
| SR-0 | `OI_ISearchProvider` abstraction + `OI_SearchService` orchestration/centralized ranking (no per-provider ranking logic) — built before any provider, since providers have nothing to plug into without it ([ADR-0017](ADR/0017-search-provider-abstraction-record-search-outside-graph.md), [SearchEngine.md §5](SearchEngine.md#5-search-provider-abstraction)) | P0 |
| SR-1 | `OI_MetadataSearchProvider` + `OI_NodeSelector.searchCurrentByText`/prefix-match fallback (SOSL Tier 1 + SOQL Tier 2, [SearchEngine.md §6–§9](SearchEngine.md#6-sosl-strategy)) — depends on SR-0, GE-3 | P0 |
| SR-2 | `Parent_Key__c` population: `OI_DiscoveredComponent.parentComponentKey` (Scanner) + pass-through (Mutation Generator) ([ADR-0018](ADR/0018-denormalized-parent-key-for-search-scoping.md), MetadataScanner.md §5/§15) — depends on MS-4a; required before SR-1's `parentKeyFilter` is meaningful | P0 |
| SR-3 | `OI_SearchController.search` / `exactLookup` — unified request/response DTOs, domain-partitioned pages, `truncated` flag ([SearchEngine.md §3, §4](SearchEngine.md#3-search-request-model)) | P0 |
| SR-4 | `oiSearchBar` component | P0 |
| SR-5 | Search result ranking tuning: `Search_Boost_Weight__c` on the Domain Type Registry, centralized ranking pass ([SearchEngine.md §14, §15](SearchEngine.md#14-ranking-strategy)) | P1 |
| SR-6 | External search index seam (only if SOSL proves insufficient at scale — see ADR-0007, [SearchEngine.md §26](SearchEngine.md#26-future-external-search-providers)) | P2 |
| SR-7 | Metadata-domain search result caching via `OI_CacheService` ([SearchEngine.md §20](SearchEngine.md#20-caching)) | P1 |

## Epic: Record Search (opt-in — sequenced after the Search epic above is solid, see SearchEngine.md §0/§29)

| # | Item | Priority |
|---|---|---|
| RS-1 | `OI_Record_Search_Scope__mdt` + `Enable_Record_Search__c` double opt-in gate ([SearchEngine.md §12](SearchEngine.md#12-record-search)) | P2 |
| RS-2 | `OI_RecordSearchProvider` + `OI_RecordSelector` (dynamic SOSL via `Search.query()`, `WITH USER_MODE`, `with sharing`) — depends on SR-0, RS-1 | P2 |
| RS-3 | `OI_Search_Records` Custom Permission | P2 |
| RS-4 | Record-result-to-Object-node bridge in `oiSearchBar` (a second, independent `exactLookup` call, never a Search-subsystem responsibility — [SearchEngine.md §23](SearchEngine.md#23-graph-engine-integration)) | P2 |

## Epic: Record Analysis (Hierarchy Visualizer — see [ADR-0021](ADR/0021-record-analysis-deferred-outside-metadata-graph.md))

**Correction (2026-08-19 code audit): this epic is done, not disabled.** The table below previously read "Analyze mode ships with Record visibly present but disabled today" — verified false by direct source read: `OI_RecordHierarchyController`/`OI_RecordHierarchyService` exist with passing tests, and `oiGraphExplorer.js:236-239,343-397` fully wires `handleRecordModeObjectSelect`/`handleRecordPicked`/`selectAndCenterRecord` to a real `getRecordFragment` call, with no `disabled` attribute on the Record tab in `oiGraphExplorer.html:27-37`. Leaving this note here rather than silently deleting it, since it's a reminder that "done" status in this backlog must be re-verified against source, not assumed from a prior pass.

| # | Item | Priority |
|---|---|---|
| RA-1 | `OI_RecordHierarchyService` — live, non-persisted read of a record's parent lookups + child relationships (`WITH USER_MODE`, `with sharing`), never written to `OI_Graph_Node__c`/`OI_Graph_Edge__c` (ADR-0021) | P2 — done |
| RA-2 | `OI_RecordHierarchyController` exposing a fragment shaped like `OI_GraphFragmentDTO` so `oiGraphCanvas`/`oiGraphNode` render it unchanged | P2 — done |
| RA-3 | Record button in `oiGraphExplorer`'s Analyze mode is enabled and wired end-to-end | P2 — done |

## Epic: Hierarchy Accelerator (new post-Phase-6 phase, see [ADR-0022](ADR/0022-hierarchy-accelerator-separate-persistence-lane.md)) — MVP fully implemented (HA-1–13); Hierarchy-2..6 (HA-14–18) remain explicitly deferred P2 phases

Admin-configured, persisted multi-hierarchy management of business records — a structurally separate subsystem from the metadata graph, coexisting with (not replacing) the Record Analysis epic above. Full design: ADR-0022. MVP scope only; see ADR-0022 for the explicitly deferred Hierarchy-2..6 phases.

| # | Item | Priority |
|---|---|---|
| HA-1 | `OI_Hierarchy_Definition__c` / `OI_Hierarchy_Level__c` schema + `OI_HierarchyDefinitionController`/`Service` (CRUD, FR-001/002) | P0 — done |
| HA-2 | `OI_Hierarchy_Relationship__c` / `OI_Hierarchy_Relationship_History__c` schema (Lookup, not Master-Detail, to Definition — ADR-0022) | P0 — done |
| HA-3 | `OI_HierarchyValidationService` — self-parent, duplicate, active-definition, effective-date-conflict, and bulk-safe in-memory circular-relationship detection bounded by `Max_Levels__c` (FR-015/016) | P0 — done |
| HA-4 | `OI_HierarchyRelationshipWriter` (renamed from the originally-planned `OI_HierarchyRelationshipRepository` — see ADR-0022) — atomic current-row + history-row commit; `OI_HierarchyRelationshipController`/`Service` (create/move/deactivate, FR-003–005, 017, 018) | P0 — done |
| HA-5 | `OI_HierarchyQueryService`/`Controller` — hierarchy-for-record, ancestors/descendants, path (FR-008–010, 012) | P0 — done. `getHierarchyMembership` (FR-008's cross-definition "Record 360" view) has no LWC consumer yet — `oiHierarchySwitcher` only lists Definitions applicable to an object type, not which ones a specific record actually currently belongs to. Backend/API only; a real, undesigned UI gap, not silently dropped. |
| HA-6 | `OI_HierarchySearchService`/`Controller` (FR-011), reusing `OI_RecordSchemaUtil` — Record Name/Id, Hierarchy Level, and Status facets only; Account Number/Location/Owner are a documented gap (no generic, object-agnostic field mapping exists for them) | P0 — done |
| HA-7 | New Custom Permissions: `OI_View_Hierarchy`, `OI_Create_Hierarchy`, `OI_Edit_Hierarchy`, `OI_Delete_Hierarchy`, `OI_Manage_Hierarchy`, `OI_View_Hierarchy_History` (FR-023, minus Import/Export) | P0 — done |
| HA-8 | Per-read object-accessibility + `WITH USER_MODE` re-check on the polymorphic parent/child reference (ADR-0022's "hard security problem") — mirrors `OI_RecordHierarchyService`'s skip-never-fail discipline | P0 — done |
| HA-9 | `oiHierarchyTree` (+ recursive `oiHierarchyTreeNode`) — literal-tree renderer (not `oiGraphCanvas`), FR-006 single-parent case | P0 — done |
| HA-10 | `oiHierarchySwitcher` (FR-007), `oiHierarchyPath` (FR-012). `oiHierarchySearchBar` (FR-011) was deliberately not built as a separate component — its spec is identical to the existing `oiRecordPicker` (search one object, return recordId/label, emit select), so `oiHierarchyManager`'s Relationships section reuses that component directly for parent/child record selection rather than duplicating its logic. | P0 — done |
| HA-11 | `oiHierarchyManager` — admin CRUD UI for Definitions/Levels (FR-001/002), AND a Relationships section (FR-003/004/005/017/018 — assign/deactivate a relationship, view history) that was missing until this pass: the component previously covered only Definitions/Levels, so despite `OI_HierarchyRelationshipController` being fully built and tested, there was no UI anywhere in the package that could actually create a hierarchy relationship. Drag-and-drop (the rest of FR-021) remains deferred to Hierarchy-3 (HA-15). | P0 — done |
| HA-12 | `oiHierarchyViewer` — Record Page integration (FR-025) composing switcher + path + tree, `NavigationMixin`-driven | P0 — done |
| HA-13 | Retention policy field (`Hierarchy_History_Retention_Days__c`, default 365) on `OI_Settings__mdt` for `OI_Hierarchy_Relationship_History__c` (no Big Object archival path yet — ADR-0022 risk; no consuming purge job either, same as `Log_Retention_Days__c`/F-7 — the field ships ahead of the batch job, an established pattern in this codebase) | P1 — done |
| HA-14 | *Hierarchy-2*: Rollup Configuration (FR-013/014), packaged reports/dashboards (FR-026) | P2 |
| HA-15 | *Hierarchy-3*: CSV Import (FR-019), Bulk Update (FR-020), Drag-and-Drop (FR-021) | P2 |
| HA-16 | *Hierarchy-4*: Hierarchy-based access (FR-022) — needs its own dedicated security design, not sketched in ADR-0022 | P2 |
| HA-17 | *Hierarchy-5*: REST/Flow surface (FR-027/028), additive-last mirroring the Integration API epic's own sequencing | P2 |
| HA-18 | *Hierarchy-6*: Automation/Notifications (FR-029/030) — no concrete trigger rules exist yet to build against | P2 |

## Epic: Hierarchy AI (new, 2026-08-19 — FRD §21 "AI Enhancement" was never translated into backlog items until now)

FRD §21 names three distinct AI capabilities: a relationship recommendation engine, duplicate/circular-risk/anomaly detection, and natural-language hierarchy search. Explicitly scoped to **natural-language search only** for now, per direct user decision — the other two (recommendation engine, anomaly detection) are acknowledged FRD scope but deliberately not started; do not build them without the user naming one specifically, same deferral discipline as HA-14..18.

Implementation approach (user-confirmed): external LLM via Named Credential (Apex callout), not Salesforce-native Prompt Builder/Models API — chosen so the feature works regardless of the customer's Data Cloud/Einstein GPT licensing. **Open, unresolved decision, deliberately left open until this epic is actually picked up:** who holds the API key — customer-supplied BYOK per org (package-safe default, no secret ever ships in the package, customer pays their own usage) vs. an ISV-hosted middleware service with a shared key (smoother install, but the ISV then owns hosting/security/per-customer cost — effectively a second product). Decide this before AI-2 starts, not before.

| # | Item | Priority |
|---|---|---|
| AI-1 | Structured query schema the NL parser must resolve to — Hierarchy Definition, Level, Status, Record Name/Id — reusing `OI_HierarchySearchService`/HA-6 as the actual search executor; the LLM only produces structured parameters, it never touches Salesforce data directly | P2 |
| AI-2 | External LLM integration via Named Credential (Apex callout) — blocked on the BYOK-vs-middleware decision above | P2 |
| AI-3 | NL input mode on the hierarchy search UI (extends HA-10's reused `oiRecordPicker`-style pattern, or a new lightweight input), falling back to the existing structured facet search on low-confidence parse — never a hard failure | P2 |

## Epic: UI Shell & Navigation (Roadmap Phase 2 & 3)

Full spec: [GraphUI.md](GraphUI.md).

| # | Item | Priority |
|---|---|---|
| UI-0 | `OI_SettingsController.getPresentationRegistry()` + `oiSharedUtils/presentationRegistry.js` fetch-once-cache module ([GraphUI.md §20, §34](GraphUI.md#20-node-type-rendering-registry)) — prerequisite for UI-2/UI-2a, since node/edge rendering has nothing to resolve styling from without it | P0 |
| UI-1 | `oiGraphExplorer` container + `graphViewState.js` (reference-counted visibility, per-node cursors, working-set ceiling — [GraphUI.md §10–§13](GraphUI.md#10-state-management)) | P0 |
| UI-2 | `oiGraphCanvas` (presentational: SVG render, radial layout, pan/zoom, virtualized rendering — [GraphUI.md §4, §17, §32](GraphUI.md#4-graph-canvas-architecture), [ADR-0019](ADR/0019-hybrid-radial-graph-visualization.md), [ADR-0020](ADR/0020-svg-rendering-vendored-layout-library.md)) | P0 |
| UI-2a | `oiGraphNode` (presentational, one per rendered node — [GraphUI.md §5](GraphUI.md#5-node-component-architecture)) — depends on UI-0 | P0 |
| UI-3 | `oiNodeDetailPanel` (`getNodeDetail` on selection; `getImpact` as a distinct, explicit action, unified into the same reference-counting model on "Highlight on Graph" — [GraphUI.md §7](GraphUI.md#7-detail-panel)) | P0 |
| UI-4 | `oiFilterPanel` (presentational — client-side visual filter + server-side `nodeTypeFilter[]`/`edgeTypeFilter[]` on subsequent expands — [GraphUI.md §22](GraphUI.md#22-filtering)) | P0 (Phase 3) |
| UI-5 | `oiBreadcrumbTrail` (presentational, center-changes only — [GraphUI.md §23](GraphUI.md#23-breadcrumbs)) | P0 (Phase 3) |
| UI-6 | `oiMiniMap` — split: Viewport Mini-map (presentational) + Frontier Summary (container, `getMiniMapSummary`) — [GraphUI.md §24](GraphUI.md#24-mini-map) | P0 (Phase 3) |
| UI-7 | `oiScanStatusPanel` (live progress via `empApi`) | P0 (Phase 1) |
| UI-8 | `oiSettingsPanel` (read-only view, links to standard Custom Metadata setup UI) | P1 |
| UI-9 | `oiAdminConsole` (log viewer, scan history) | P1 |
| UI-10 | Dark mode | P1 |
| UI-11 | Full keyboard navigation + ARIA audit | P1 |
| UI-12 | Context menus on graph nodes | P2 |

## Epic: Graph Canvas Layout Quality (new, 2026-08-19 — closes the "unstructured/ugly canvas" complaint, highest priority per user sequencing)

**Why this epic exists:** a 2026-08-19 code audit confirmed `oiGraphCanvas`'s ring-assignment layout (`oiGraphCanvas.js:568-681`) is real and correctly tested for simple tree fixtures (BFS ring placement, per-ring radius sized off cumulative node footprint, pairwise distance ≥150 asserted in `oiGraphCanvas.test.js:164-188`). The chaotic appearance on real org data is not a CSS or anchor bug — it's a documented, deliberate MVP scope cut: `oiGraphCanvas.js:33-36` states outright that no force-relaxation/edge-crossing-reduction pass exists, even though `GraphUI.md:266` and ADR-0020 ("Accepted") both specify one. Real org graphs have hub nodes (User, RecordType, Owner, etc.) referenced from many unrelated branches/rings; every edge to them still renders as a straight/curved chord with no crossing-minimization or bundling, which is what reads as "no clear layout pattern." Separately, the user also flagged the rendered nodes/edges as visually unpolished — a pre-existing, previously-flagged quality bar (contrast, spacing, label truncation verified against real rendered chrome, not estimated) that has not yet been re-verified against current output.

| # | Item | Priority |
|---|---|---|
| UI-13 | Force-relaxation / edge-crossing-reduction pass per `GraphUI.md` §17/§32 — implemented 2026-08-19 as an in-house barycenter-reordering heuristic (`oiGraphCanvas.js`'s `computeBaseLayout`, passes 2–3), not a vendored library — see [ADR-0020's amendment](ADR/0020-svg-rendering-vendored-layout-library.md#amendment-2026-08-19-the-layout-math-library-was-implemented-in-house-not-vendored) for why. All 207 LWC Jest tests pass, including a new hub-node case (UI-16) | P0 — done |
| UI-14 | Hub-node handling: a node referenced from multiple currently-expanded ancestors (GraphUI.md §18) is now pulled toward the angular barycenter of ALL its real connections (not just its one BFS parent), and any edge outside the BFS tree renders with a reduced-opacity `oi-graph-edge-secondary` style so it recedes visually without being hidden (ADR-0019's topological-honesty guarantee preserved) | P0 — done |
| UI-15 | Visual polish pass on `oiGraphNode`/`oiGraphCanvas` re-verified against real rendered screenshots (not estimated dimensions) — contrast, spacing, label truncation, icon/chrome legibility at normal sizes. **Not done**: source review (2026-08-19) shows contrast/spacing were already reasonably addressed in a prior pass (SLDS token hooks throughout, edge contrast already widened per an existing code comment), but this still needs verification against actual rendered output in a real org, which no session so far has done | P0 |
| UI-16 | Jest fixture covering a shared/hub-node, cross-link graph shape (not just a simple tree) so the crossing-edges gap is guarded going forward — added 2026-08-19 (`oiGraphCanvas.test.js`, the root→A,B→hub diamond case), asserting the hub lands within the angular span between its two real parents | P1 — done |

## Epic: Package Readiness & Security (Roadmap Phase 5)

| # | Item | Priority |
|---|---|---|
| PK-1 | Package ancestry + semantic versioning discipline | P0 |
| PK-2 | Full CRUD/FLS/sharing audit across every Selector/Repository | P0 |
| PK-3 | Static resource CSP / third-party license audit | P0 |
| PK-4 | Contract test suite for Tooling/Metadata/Describe response shapes | P0 |
| PK-5 | Internal Security Review dry-run against Salesforce's published checklist | P0 |
| PK-6 | Uninstall data-export guidance/documentation | P1 |

## Epic: Integration API (Roadmap Phase 6)

| # | Item | Priority |
|---|---|---|
| IA-1 | `@RestResource` `/graph/{nodeKey}`, `/impact/{nodeKey}`, `/search` | P1 |
| IA-2 | `@RestResource` `/scans` (POST/GET) | P1 |
| IA-3 | REST response envelope + error sanitization parity with internal API | P1 |
| IA-4 | API documentation/examples for CI/CD "impact check before deploy" use case | P2 |

## Epic: Post-GA Candidates (unscheduled)

| # | Item | Priority |
|---|---|---|
| PG-1 | Org health scoring (composite metric across technical-debt signals) | P2 |
| PG-2 | Technical-debt dashboard views | P2 |
| PG-3 | Historical trend views over the Big Object edge archive | P2 |
| PG-4 | Deeper Reports/Dashboards graph enrichment (e.g. report-to-field usage edges) | P2 |
| PG-5 | Multi-org comparison (sandbox vs. production drift) | P2 |

---

## Grooming Notes

- No item above should be started without first re-reading the relevant Architecture.md section and, if the item touches a decision an ADR already covers, the ADR — this backlog is downstream of those documents, not a substitute for them.
- Items marked P0 within Phase 3+ are only P0 *relative to their phase* — they are not required before Phase 1/2 ship; see [Roadmap.md](Roadmap.md) for phase sequencing and its rationale.

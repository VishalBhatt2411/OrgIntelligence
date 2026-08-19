# Roadmap — Salesforce Org Intelligence Platform

Status: Draft v1

This roadmap sequences delivery by architectural dependency, not by calendar date (no dates are committed here — durations are relative sizing for planning only). Each phase produces something demonstrable and testable; no phase assumes a later phase's engine already exists. See [Backlog.md](Backlog.md) for the itemized breakdown behind each phase.

---

## Phase 0 — Foundation (prerequisite for everything else)

Nothing product-visible yet; this is the skeleton every later engine builds on.

- Layered folder structure, naming conventions, and base classes in place (`OI_ApplicationException` hierarchy, `OI_LoggerService`, `OI_SecurityService`).
- `OI_Settings__mdt`, `OI_Metadata_Type_Config__mdt` schema deployed with sensible defaults.
- `OI_Graph_Node__c`, `OI_Graph_Edge__c`, `OI_Scan_Run__c`, `OI_Scan_Task__c`, `OI_Log__c` deployed (schema only, per [DataModel.md](DataModel.md)).
- Custom Permissions + `OI_Viewer`/`OI_Power_User`/`OI_Administrator` Permission Sets shipped.
- CI pipeline (scratch org → deploy → test → destroy) operational.

**Exit criteria**: an empty package installs cleanly into a fresh scratch org, all Phase 0 tests pass, no functional UI yet.

---

## Phase 1 — Metadata Scanner MVP

- `OI_IMetadataScanner` strategy interface + orchestrator (`OI_ScanOrchestratorQueueable`) with chaining, failure isolation, and `OI_Scan_Run__c`/`OI_Scan_Task__c` status tracking.
- First scanners: `OI_ObjectScanner`, `OI_FieldScanner`, `OI_ApexClassScanner` (three types is enough to prove the Strategy pattern and the Describe/Tooling API adapters without building all ~15 scanners up front).
- `OI_ToolingApiAdapter`, `OI_DescribeApiAdapter` (Integration layer).
- Full-scan mode only (incremental deferred to Phase 3 once there's a baseline to diff against).
- `OI_Scan_Progress__e` + minimal `oiScanStatusPanel` to observe a scan running end-to-end.

**Exit criteria**: triggering a scan against a scratch org populates `OI_Graph_Node__c` for objects/fields/Apex classes, visible progress, correlatable logs.

---

## Phase 2 — Graph Engine + Minimal Graph UI

- `OI_GraphRepository` + Storage Providers built first (nothing else in the Graph Engine can function without it — [ADR-0012](ADR/0012-graph-repository-storage-gateway.md)), then `OI_GraphBuilder` (versioned ingestion, [ADR-0014](ADR/0014-immutable-node-edge-versioning.md)) and `OI_GraphTraversal` (expand/filter), then the `OI_GraphEngine` facade composing both ([ADR-0013](ADR/0013-graphengine-facade.md)); `OI_NodeSelector`/`OI_EdgeSelector` throughout.
- `OI_GraphController.getGraphFragment` / `getNodeDetail` — calling `OI_GraphEngine` only, never its internals.
- `OI_SettingsController.getPresentationRegistry()` before the Canvas, since registry-driven rendering has nothing to resolve styling from without it (Backlog UI-0, [GraphUI.md §20](GraphUI.md#20-node-type-rendering-registry)).
- `oiGraphExplorer` shell (container/presentational split, [GraphUI.md §3](GraphUI.md#3-component-architecture)) + `oiGraphCanvas`/`oiGraphNode` (basic render: pan/zoom/expand/collapse, radial layout, no mini-map yet) + `oiNodeDetailPanel`.
- Client-side view-state module (Architecture §10, full model [GraphUI.md §10–§13](GraphUI.md#10-state-management)) introduced here, before any second component needs it — validates the "no heavy state library" decision (ADR-0008) against a real second consumer.
- L1 Platform Cache wired for graph fragments (Architecture §11), invalidation still coarse (full-node-type flush acceptable at this stage; neighborhood-scoped invalidation lands in Phase 3 alongside incremental scanning, since it depends on the scanner knowing exactly what changed).

**Exit criteria**: a user can visually browse objects → fields → classes as a graph, click to expand, see detail panel — the core "Google Maps for metadata" experience is demonstrable, even if only 3 node types deep.

---

## Phase 3 — Incremental Scanning + Remaining Scanners + Precise Caching

- Checksum-based delta detection in the scanner base (Architecture §6/ADR-0009); `OI_Scan_Task__c.Records_Changed__c` becomes meaningful.
- Remaining scanners: Flow, ValidationRule, PermissionSet, Profile, Trigger, LWC, AuraComponent, NamedCredential, Dashboard, Report, Package (prioritized by customer-value feedback from Phase 1–2 pilots, not fixed order).
- `OI_Cache_Invalidation__e` + neighborhood-scoped L1 eviction replaces the coarse Phase 2 flush.
- `oiFilterPanel`, `oiBreadcrumbTrail`, `oiMiniMap`, `oiSearchBar` (Metadata domain, SOSL typeahead only — [SearchEngine.md](SearchEngine.md); Record Search stays Post-GA) complete the primary UI shell.
- Self-imposed API call budget tracking (`OI_Scan_Run__c.Api_Call_Budget_Used__c`, `OI_Settings__mdt.Daily_Api_Call_Budget__c`).

**Exit criteria**: full metadata surface scanned, rescans are fast and cheap for unchanged orgs, primary navigation UX (search/filter/breadcrumb/mini-map) complete.

---

## Phase 4 — Dependency Engine (Impact Analysis)

- `OI_DependencyEngineService` (forward/reverse traversal, cycle detection), `OI_Impact_Analysis_Cache__c`.
- `OI_DependencyController.getImpact`, impact view surfaced in `oiNodeDetailPanel` (graph + flat-list dual rendering, per `CLAUDE.md` §UI Philosophy tables-are-secondary rule).
- This phase is deliberately after the Graph Engine is stable, since Dependency Engine is a read-only consumer of graph edges (Architecture §7) and gains nothing from starting earlier.

**Exit criteria**: "what breaks if I change this field/class" is answerable in the UI, backed by real edge data across all Phase 3 scanners.

---

## Phase 5 — Security Hardening, Package Readiness, Big Object Archival

- `OI_InstallHandler`, package ancestry established, versioning discipline in place (Architecture §15).
- Big Object archival (`OI_Graph_Edge_Archive__b`) and log/impact-cache retention batch jobs (Architecture §17, DataModel §7) — needed once real usage produces enough history to matter, not before.
- Full Security Review pass: CRUD/FLS/sharing audit across every Selector/Repository, static resource CSP audit, Named Credential usage audit (if any external calls have been introduced by this point — expected none in v1).
- Contract tests for Tooling/Metadata/Describe API response shapes finalized as a standing CI suite.

**Exit criteria**: package passes an internal AppExchange Security Review dry-run; storage/retention housekeeping jobs are live and tested.

---

## Phase 6 — Integration API + AppExchange Submission

- `@RestResource` surface ([API.md §3](API.md#3-integration-api--rest-resources)) — deliberately last, since it's additive on top of an already-stable Service layer (Architecture §3 boundary rule is what makes this low-risk to add late).
- AppExchange listing assets, submission, formal Salesforce Security Review.

**Exit criteria**: listed on AppExchange.

---

## Phase 7 — Hierarchy Accelerator (MVP)

A new, structurally separate subsystem (see [ADR-0022](ADR/0022-hierarchy-accelerator-separate-persistence-lane.md)) — admin-configured, persisted multi-hierarchy management of business records, coexisting with (not replacing) the live-query Record Analysis feature from Phase 2. Sequenced after Phase 6 since it has no dependency on the Integration API and nothing in Phases 0–6 depends on it.

- `OI_Hierarchy_Definition__c`/`OI_Hierarchy_Level__c`/`OI_Hierarchy_Relationship__c`/`OI_Hierarchy_Relationship_History__c` schema.
- `OI_HierarchyDefinitionService`, `OI_HierarchyRelationshipService` (atomic current-row + history-row commit), `OI_HierarchyValidationService` (circular-relationship detection, bulk-safe), `OI_HierarchyQueryService`, `OI_HierarchySearchService`.
- New Custom Permissions (`OI_View_Hierarchy`, `OI_Create_Hierarchy`, `OI_Edit_Hierarchy`, `OI_Delete_Hierarchy`, `OI_Manage_Hierarchy`, `OI_View_Hierarchy_History`) and the per-read object-accessibility re-check ADR-0022 requires for the polymorphic parent/child reference.
- `oiHierarchyTree` (literal tree, not the radial `oiGraphCanvas`), `oiHierarchySwitcher`, `oiHierarchyPath`, `oiHierarchySearchBar`, `oiHierarchyManager`, Record Page integration.

**Exit criteria**: an admin can define a hierarchy type, assign records to it, view ancestors/descendants/path in a tree, and see relationship history — the FRD's MVP scope (FR-001–003, 005–012, 015–018, 023–025), not the full 30-requirement document. Rollups, CSV import/bulk update/drag-and-drop, hierarchy-based access, REST/Flow, and automation/notifications are explicitly deferred, named future phases (ADR-0022, Backlog.md Epic: Hierarchy Accelerator HA-14..18) — not attempted here.

---

## Post-GA / Backlog-Driven

Everything not required to reach a sellable v1 lives in [Backlog.md](Backlog.md), prioritized independently of this roadmap — e.g., an external search index behind `OI_SearchService` (only if SOSL's characteristics prove insufficient at real customer scale — ADR-0007 explicitly defers this), **Record Search** (opt-in, off by default, deliberately sequenced after the metadata search experience is solid — [SearchEngine.md §0, §29](SearchEngine.md#0-relationship-to-prior-documents--what-this-corrects-adds-and-challenges), Backlog Epic: Record Search), org-health scoring, technical-debt dashboards, historical trend views over the Big Object archive, and any Reports/Dashboards-specific graph enrichment beyond basic node presence.

---

## Sequencing Rationale (why this order and not another)

- **Scanner before Graph Engine** — the Graph Engine has nothing to build without normalized scanner output; building it first would mean mocking scanner output indefinitely.
- **Graph Engine before Dependency Engine** — Dependency Engine is explicitly read-only over the graph (Architecture §7); there's no reason to build traversal logic against data that doesn't exist yet.
- **Full-scan before incremental** — incremental scanning is a diff against a prior state; Phase 1 has to produce that prior state before Phase 3's diff logic has anything to diff against.
- **Coarse caching before precise invalidation** — neighborhood-scoped cache invalidation (Architecture §11) depends on the scanner's checksum/delta mechanism (Phase 3), so Phase 2 intentionally ships a simpler, coarser cache to avoid blocking the first visual milestone on a Phase-3 capability.
- **Integration API last** — it is purely additive per the layering rules in Architecture §4; nothing else depends on it, so it carries zero risk to defer and validates that the Service-layer boundary actually holds up as a reuse seam.

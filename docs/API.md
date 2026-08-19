# API — Salesforce Org Intelligence Platform

Status: Draft v1
Applies to: API v67.0

This document defines the platform's API surface at two levels:

1. **Internal API** — the `@AuraEnabled` Controller contracts LWCs call. This is the primary, most-used surface.
2. **Integration API** — a versioned `@RestResource` surface for programmatic/external access (CI/CD tooling, other AppExchange apps, admin scripting), reached under `/services/apexrest/OI/v1/...`.

No business logic or implementation appears here — only contracts: inputs, outputs, error semantics, and access requirements. All shapes are DTOs, never raw `OI_Graph_Node__c`/`OI_Graph_Edge__c` sObjects (Controllers never return sObjects directly — see [CodingStandards.md](CodingStandards.md)).

---

## 1. Design Rules for This API Surface

- **Controllers are thin.** Every method: check Custom Permission → call one Service method → map result to a DTO → return. No branching on business rules in a Controller.
- **Graph-related Controllers call `OI_GraphEngine` exclusively.** `OI_GraphController` and `OI_DependencyController` below have no dependency on `OI_GraphBuilder`, `OI_GraphTraversal`, `OI_GraphRepository`, `OI_GraphSerializer`, or `OI_GraphCache` — those are internal to the Graph Engine facade and are never referenced outside it, by a Controller or any other Service ([GraphEngine.md §1.1](GraphEngine.md#11-graphengine-facade--the-only-public-entry-point), [ADR-0013](ADR/0013-graphengine-facade.md)).
- **`OI_SearchController` calls `OI_SearchService` exclusively, and `OI_SearchService` never calls `OI_GraphEngine` in either direction.** Search and graph traversal are separate concerns by construction — a search result's `nodeKey` is a pointer the *UI* hands to `OI_GraphController` on a separate, later call, never something Search resolves itself ([SearchEngine.md §22, §23](SearchEngine.md#23-graph-engine-integration)).
- **Every method documents**: required Custom Permission, inputs, output shape, and thrown-exception-to-user-message mapping (Architecture §12/§14).
- **Cacheable where safe.** Read-only, side-effect-free methods are `@AuraEnabled(cacheable=true)` to let LWC `@wire` benefit from client-side caching; mutating methods are not.
- **Pagination is mandatory** on every method that can return more than a small bounded set (graph fragments, search results, scan history) — no method returns an unbounded list.
- **Versioning**: the Integration REST API is explicitly versioned in its URL (`/v1/`); the internal Apex API is versioned implicitly by package version and is not intended for use outside this package's own LWCs.

---

## 2. Internal API — Apex Controllers

### 2.1 `OI_GraphController`
Backs `oiGraphExplorer` / `oiGraphCanvas`. Calls `OI_GraphEngine` only. Full contract detail, including the two additions below, is in [GraphEngine.md §18](GraphEngine.md#18-api-contracts-between-apex-and-lwc).

| Method | Required Permission | Input | Output |
|---|---|---|---|
| `getGraphFragment` | `OI_View_Graph` | `nodeKey`, `hopDepth` (capped by `Max_Hop_Depth__c`), `nodeTypeFilter[]`, `edgeTypeFilter[]`, `pageCursor`, **`knownChecksums` (optional map of already-held node keys to their last-seen checksum, enabling delta-only responses on repeat visits — GraphEngine.md §9)** | `OI_GraphFragmentDTO` (`nodes[]` — key/typeKey/label/secondaryKey/state only, never full attributes; `edges[]`; **`frontier[]` — node keys in this response with unexplored neighbors, GraphEngine.md §4**; **`retiredKeys[]` — previously-held keys the client should discard**; `hasMore`; `nextCursor`) |
| `getNodeDetail` | `OI_View_Graph` | `nodeKey` | `OI_NodeDetailDTO` (full attributes, last-scanned info, soft-delete state) — the only method that returns full attributes; fetched on demand, never bundled into bulk fragment responses (GraphEngine.md §10) |
| `getMiniMapSummary` | `OI_View_Graph` | `nodeKey`, `radius` | `OI_MiniMapDTO` (coarse node/edge counts by `typeKey`, not full detail) |

**Errors**: `OI_SecurityException` → "You don't have permission to view org graph data."; `OI_ValidationException` (e.g. hop depth exceeding ceiling) → message naming the configured max; unexpected → generic "Something went wrong retrieving the graph. Support ID: {correlationId}".

### 2.2 `OI_SearchController`
Backs `oiSearchBar`. Calls `OI_SearchService` only — never `OI_NodeSelector`/`OI_RecordSelector` directly, and never `OI_GraphEngine`/`OI_GraphTraversal` in either direction ([SearchEngine.md §2, §22, §23](SearchEngine.md#2-search-architecture)). Full contract detail is in [SearchEngine.md §3, §4](SearchEngine.md#3-search-request-model).

| Method | Required Permission | Input | Output |
|---|---|---|---|
| `search` | `OI_View_Graph` (`Metadata` domain); **`OI_Search_Records`, additionally, for the `Record` domain** | `OI_SearchRequestDTO` (`query`, `domains[]` — defaults `{Metadata}`, `typeFilter[]`, **`parentKeyFilter`**, `sObjectFilter[]` — Record domain only, `pageSize`, `pageCursor`) | `OI_SearchResponseDTO` (`pages: Map<domain, DomainResultPage>` — each with `results[]` discriminated by `resultKind`, `hasMore`, `nextCursor`, **`truncated`**) — Metadata results carry `nodeKey`/`typeKey`/`label`/`secondaryKey`/`parentKey`; Record results carry `recordId`/`sObjectApiName`/`displayName` and **no `nodeKey`** (records are not graph nodes, [SearchEngine.md §4, §12](SearchEngine.md#4-search-response-model)) |
| `exactLookup` | `OI_View_Graph` | `secondaryKey`, `typeKey` (optional), **`parentKey` (optional)** | `OI_NodeSummaryDTO` or null |

**Record Search is silently a no-op, never an error**, if `OI_Settings__mdt.Enable_Record_Search__c` is `false` or a requested sObject isn't configured/enabled — the `Record` domain's page simply returns empty ([SearchEngine.md §25](SearchEngine.md#25-error-handling)).

### 2.3 `OI_DependencyController`
Backs impact-analysis views in `oiNodeDetailPanel`. Calls `OI_DependencyEngineService`, which itself reaches the graph only through `OI_GraphEngine` — never `OI_GraphTraversal`/`OI_GraphRepository` directly (Architecture §4, ADR-0013).

| Method | Required Permission | Input | Output |
|---|---|---|---|
| `getImpact` | `OI_View_Graph` | `nodeKey`, `direction` (`Forward`/`Reverse`), `depth` | `OI_ImpactResultDTO` (affected subgraph + flat list, served from `OI_Impact_Analysis_Cache__c` when fresh) |

### 2.4 `OI_ScanController` — Implemented, Sprint 9
Backs `oiScanStatusPanel` / admin console. Calls `OI_ScanOrchestratorQueueable` only — no
separate Service class exists for scan lifecycle (Sprint 8 established this class as that
surface; Sprint 9 extended it rather than introducing a parallel Service).

| Method | Required Permission | Input | Output |
|---|---|---|---|
| `startScan` | `OI_Run_Scan` | `scanType` (`Full`/`Incremental`), `metadataTypeOverride[]` (optional subset) | `OI_ScanRunSummaryDTO` (runId, status) — throws `OI_ServiceException` (translated to a sanitized `AuraHandledException`) if a scan is already `Running` (the single-flight guard, [MetadataScanner.md §13](MetadataScanner.md#13-scan-scheduling)); would throw `OI_SecurityException` if the running user lacked the platform-level Tooling/Metadata API permission the scan itself requires (Architecture §14) — not separately enforced here beyond the Custom Permission check, since Describe/SOQL (this sprint's 3 scanners) need no additional platform permission |
| `getScanStatus` | `OI_Run_Scan` | `scanRunId` | `OI_ScanRunSummaryDTO` (also reachable via `OI_Scan_Progress__e` push — corrected object API name; the platform event follows `CodingStandards.md §1`'s `OI_<Noun>__e` convention exactly like every other object in this platform, matching its own naming-table example) |
| `getScanHistory` | `OI_Run_Scan` | `pageSize`, `pageCursor` (opaque — a `String.valueOf(Datetime)` cursor over `CreatedDate`, round-tripped via `Datetime.valueOf`) | `OI_ScanRunSummaryDTO[]` |
| `cancelScan` | `OI_Run_Scan` | `scanRunId` | void — best-effort; the in-flight chained Queueable hop completes (marking any in-progress `OI_Scan_Task__c` `Skipped`), the next hop checks the run's status at the top of `execute()` and does not enqueue further work |

### 2.5 `OI_SettingsController`
Backs `oiSettingsPanel` **and** `oiGraphExplorer`'s registry fetch ([GraphUI.md §20, §34](GraphUI.md#20-node-type-rendering-registry)).

| Method | Required Permission | Input | Output |
|---|---|---|---|
| `getSettings` | `OI_Manage_Settings` | — | `OI_SettingsDTO` (current `OI_Settings__mdt` + `OI_Metadata_Type_Config__mdt` rows) |
| `getLogEntries` | `OI_View_Logs` | `level`, `correlationId`, `pageSize`, `pageCursor` | `OI_LogEntryDTO[]` |
| `getPresentationRegistry` | **none** — no Custom Permission required ([GraphUI.md §30](GraphUI.md#30-security)); baseline authenticated access only | — | `List<OI_NodeTypeDescriptorDTO>` (`typeKey`, `displayLabel`, `iconName`, `colorToken`), `List<OI_EdgeTypeDescriptorDTO>` (`typeKey`, `displayLabel`, `lineStyle`) — `@AuraEnabled(cacheable=true)`; resolves [GraphEngine.md §17](GraphEngine.md#17-rendering-contract-for-lwc)'s previously-open registry-delivery question in favor of a runtime Custom Metadata read, fetched once per session and client-cached, never a build-time-baked static resource |

Note: Custom Metadata is not DML-writable from Apex at runtime in a subscriber org without Metadata API deployment; `OI_SettingsController` is read-only. Settings changes ship as either package upgrades (defaults) or are exposed through the standard Custom Metadata setup UI, linked from `oiSettingsPanel` rather than reimplemented — avoids building a redundant, weaker CRUD UI for something the platform already provides.

---

## 3. Integration API — REST Resources

Exposed for programmatic access (CI/CD gates checking impact before a deploy, other tooling querying org health). Session- or Connected-App-OAuth-authenticated; subject to the same Custom Permission checks as the internal API — the REST layer is not a bypass.

Base path: `/services/apexrest/OI/v1`

| Resource | Method | Required Permission | Purpose |
|---|---|---|---|
| `/graph/{nodeKey}` | `GET` | `OI_View_Graph` | Equivalent of `getGraphFragment`, query-string params for hop depth/filters/cursor |
| `/impact/{nodeKey}` | `GET` | `OI_View_Graph` | Equivalent of `getImpact` — the highest-value integration use case: "will changing this break anything," callable from a CI pipeline before deploy |
| `/search` | `GET` | `OI_View_Graph` | Equivalent of `search`, query param `q` |
| `/scans` | `POST` | `OI_Run_Scan` | Equivalent of `startScan` — enables CI-triggered rescans after a deploy |
| `/scans/{scanRunId}` | `GET` | `OI_Run_Scan` | Equivalent of `getScanStatus` |

**Response envelope** (all endpoints): `{ "data": {...}, "correlationId": "...", "hasMore": bool, "nextCursor": "..." }` on success; `{ "error": { "code": "...", "message": "...", "correlationId": "..." } }` on failure — same sanitization rule as the internal API (Architecture §12): no stack traces, no internal field/object names ever cross this boundary.

**Rate/limit behavior**: subject to the same self-imposed Tooling/Metadata API budget as internal-triggered scans (Architecture §17); a `POST /scans` that would exceed the daily budget returns `429`-equivalent (`{"error":{"code":"BUDGET_EXCEEDED", ...}}`) rather than partially executing.

This surface is intentionally the *last* thing built (see [Roadmap.md](Roadmap.md)) — it is additive on top of the same Service layer the internal Controllers use, so it ships without touching Graph/Scanner/Dependency engine internals.

---

## 4. Event Contracts (async, not request/response)

| Event | Direction | Consumer | Purpose |
|---|---|---|---|
| `OI_Scan_Progress__e` | Server → Client (via `empApi`) | `oiScanStatusPanel` | Live scan progress without polling |
| `OI_Cache_Invalidation__e` | Server → Server | `OI_GraphCache` subscriber trigger (internal to the `OI_GraphEngine` facade) | Neighborhood-scoped L1 cache eviction, fired on a new version — never on a liveness-only touch |
| `OI_Log_Event__e` | Server → Server | `OI_LogRepository` subscriber trigger | Decoupled, async log persistence |

Full field definitions: [DataModel.md §5](DataModel.md#5-platform-events).

---

## 5. Explicitly Out of Scope for v1

- No public unauthenticated endpoints (all access requires an authenticated Salesforce session or Connected App OAuth grant, gated by Custom Permission).
- No GraphQL surface — the bounded, purpose-built DTOs above cover the actual UI/integration needs without the operational cost of a general query surface (revisit only if a concrete third-party integration need emerges — see Backlog).
- No write access to customer business metadata via this API — the platform is read-only/observational with respect to the org it scans; it never mutates scanned metadata.
- **Record Search is internal-API-only in v1** — the `/search` REST resource remains Metadata-domain only; Record Search ([SearchEngine.md §12](SearchEngine.md#12-record-search)) is not exposed via the Integration API, consistent with its opt-in, off-by-default posture and the vision-scope caution recorded in [SearchEngine.md §0](SearchEngine.md#0-relationship-to-prior-documents--what-this-corrects-adds-and-challenges). Revisit if/when Record Search itself graduates out of opt-in.

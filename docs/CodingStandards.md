# Coding Standards — Salesforce Org Intelligence Platform

Status: Draft v1

This document operationalizes `CLAUDE.md`'s standing rules into concrete, checkable conventions. Where `CLAUDE.md` states a principle (e.g. "bulkify everything"), this document states how compliance is recognized in review. Nothing here overrides `CLAUDE.md`; if the two ever conflict, `CLAUDE.md` wins and this document should be corrected.

---

## 1. Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Apex class (Controller) | `OI_<Noun>Controller` | `OI_GraphController` |
| Apex class (Facade — Graph Engine only) | `OI_<Noun>Engine` | `OI_GraphEngine` — the *only* public entry point for anything graph-related; see §2 |
| Apex class (Service) | `OI_<Noun>Service` | `OI_MetadataScanService`, `OI_DependencyEngineService` |
| Apex class (Graph Engine internal) | `OI_Graph<Role>` | `OI_GraphBuilder`, `OI_GraphTraversal`, `OI_GraphSerializer`, `OI_GraphCache` — never referenced outside `OI_GraphEngine`; see §2 |
| Apex class (Selector) | `OI_<Noun>Selector` | `OI_NodeSelector` |
| Apex class (Repository) | `OI_<Noun>Repository` | `OI_GraphRepository` — the *only* class that touches storage for graph data |
| Apex class (Storage Provider) | `OI_<Backend>StorageProvider` | `OI_CustomObjectStorageProvider`, `OI_BigObjectStorageProvider`, `OI_PlatformCacheStorageProvider` — used only by `OI_GraphRepository` |
| Apex class (Search Provider) | `OI_<Domain>SearchProvider` | `OI_MetadataSearchProvider`, `OI_RecordSearchProvider` — used only by `OI_SearchService` ([SearchEngine.md §5](SearchEngine.md#5-search-provider-abstraction)) |
| Apex class (Adapter) | `OI_<Api>Adapter` | `OI_ToolingApiAdapter` |
| Apex class (Scanner strategy) | `OI_<MetadataType>Scanner` | `OI_FlowScanner` |
| Apex interface | `OI_I<Capability>` | `OI_IMetadataScanner`, `OI_IGraphStorageProvider` |
| Apex exception | `OI_<Noun>Exception` | `OI_SecurityException` |
| Apex DTO | `OI_<Noun>DTO` | `OI_GraphFragmentDTO` |
| Apex domain object (**immutable** — no setters; a "change" returns a new instance) | `OI_<Noun>` (no suffix) | `OI_Node`, `OI_Edge` |
| Async Apex | `OI_<Noun>Queueable` / `OI_<Noun>Batch` / `OI_<Noun>Schedulable` | `OI_ScanOrchestratorQueueable` |
| Test class | `<ClassUnderTest>Test` | `OI_GraphBuilderTest`, `OI_GraphRepositoryTest`, `OI_GraphEngineTest` |
| Custom Object | `OI_<Noun>__c` | `OI_Graph_Node__c` |
| Custom Metadata Type | `OI_<Noun>__mdt` | `OI_Settings__mdt` |
| Platform Event | `OI_<Noun>__e` | `OI_Scan_Progress__e` |
| Custom Permission | `OI_<Verb>_<Noun>` | `OI_Run_Scan` |
| LWC | `oi<PascalCaseNoun>` (camelCase folder, per LWC convention) | `oiGraphCanvas` |

No physical Apex subfolders — logical grouping is 100% naming convention (`CLAUDE.md` §Apex Organization). A reviewer should be able to tell a class's layer from its name alone.

---

## 2. Layering Rules (enforced in review, not just described)

- A **Controller** method body is: permission check → one Service call → DTO map → return/throw translation. Any `if` statement branching on business data (not on permission/input-shape) in a Controller is a review blocker.
- A **Service** never contains inline SOQL/SOSL or `HttpRequest` — those always go through a Selector/Repository or Adapter respectively.
- A **Selector** returns sObjects or projections thereof only to Repositories/Services — never directly to a Controller.
- A **Domain** class (`OI_Node`, `OI_Edge`, `OI_ImpactResult`, etc.) has zero dependencies on `Database.*`, `Http*`, or any `@AuraEnabled` annotation — it is constructible and testable with no org context at all.
- Cross-service calls only through another service's public methods (Architecture §4) — reaching into another service's Selector/Repository is a review blocker.
- **Graph Engine facade rule** ([ADR-0013](ADR/0013-graphengine-facade.md)): nothing outside `OI_GraphEngine` references `OI_GraphBuilder`, `OI_GraphTraversal`, `OI_GraphRepository`, `OI_GraphSerializer`, or `OI_GraphCache` by name — including other Services (`OI_DependencyEngineService`, `OI_SearchService`) and every Controller. A `new OI_Graph<Role>(...)` or a static call to one of those classes anywhere outside `OI_GraphEngine`'s own implementation is a review blocker, no exceptions. `OI_GraphEngine` itself contains no business logic — every one of its methods is a pass-through to exactly one (occasionally two) internal component; logic that doesn't fit that shape belongs in the component, not the facade.
- **Graph Builder never touches storage** ([ADR-0012](ADR/0012-graph-repository-storage-gateway.md)): `OI_GraphBuilder` calls `OI_GraphRepository` for every read and write; a SOQL query, DML statement, or `Cache.Org` call inside `OI_GraphBuilder` itself is a review blocker.
- **`OI_SearchService` never contains inline SOSL/SOQL, and never calls `OI_GraphTraversal`/`OI_GraphEngine` in either direction** ([SearchEngine.md §0, §22, §23](SearchEngine.md#0-relationship-to-prior-documents--what-this-corrects-adds-and-challenges)): every search read goes through `OI_NodeSelector`/`OI_RecordSelector`; a `[FIND ...]`/`[SELECT ...]` literal or a `Search.query()` call inside `OI_SearchService` itself, or any call from `OI_SearchService` into anything Graph-Engine-facade-internal, is a review blocker.
- **`OI_GraphRepository` never constructs SOQL inline** ([GraphRepository.md §12](GraphRepository.md#12-query-strategy--selector-delegation)): every Custom Object read it needs is delegated to `OI_NodeSelector`/`OI_EdgeSelector`, exactly like every other Repository in the platform — a `[SELECT ...]` literal inside `OI_GraphRepository` (or a Storage Provider) is a review blocker, not an exception this class earns by being the most complex Repository.
- **Version commits are atomic, not two-step** ([ADR-0016](ADR/0016-repository-atomic-commit-and-optimistic-concurrency.md)): `OI_GraphRepository.commitVersion` is the only public method permitted to `insert` a new `OI_Graph_Node__c`/`OI_Graph_Edge__c` version row. Any new public method that inserts against those objects outside `commitVersion` — even one that seems to only need "the insert half" — is a review blocker; it reopens exactly the partial-write corruption window `commitVersion` exists to close ([GraphRepository.md §21](GraphRepository.md#21-risks)).

## 3. Trigger Rules

Exactly per `CLAUDE.md` §Trigger Rules: one trigger per object, trigger body only validates context and delegates to a single handler class; the handler contains no business logic itself, only bulk-safe delegation to a Service. Always bulkified (assume up to 200 records); explicit recursion guard where the handler could otherwise re-enter (e.g., via a Service call that itself performs DML on the same object).

## 4. SOQL/SOSL & Data Access

- No inline SOQL/SOSL outside Selectors, without documented justification (e.g. a one-off diagnostic script under `scripts/`, which is not shipped in the package).
- All Selector/Repository queries touching **customer business data** (i.e., data reachable through scanned metadata, not the app's own `OI_*__c` tables) run `WITH USER_MODE`; app-internal object access follows the Apex-boundary model in Architecture §14/ADR-0006, not object-level CRUD.
- Every SOQL query used inside a loop context is a review blocker — no exceptions. Selectors are written to accept bulk key sets (`Set<String> nodeKeys`), not single keys, as their primary shape; single-key convenience overloads simply wrap the bulk form.
- Explicit field lists only — no `SELECT *` equivalents (`SELECT Id FROM ... ` style unbounded field pulls); a Selector method's returned fields are exactly what its declared return DTO/contract needs.
- Every query against `OI_Graph_Node__c`/`OI_Graph_Edge__c` outside an explicit version-history feature includes `WHERE Is_Current__c = true` — centralized inside the Selector method itself, never left for the caller to remember (GraphEngine.md §13/§15/§21, [ADR-0014](ADR/0014-immutable-node-edge-versioning.md)). A Selector method that takes an `Is_Current__c` parameter instead of hardcoding the predicate is a review flag — the only legitimate caller of "give me a non-current version" is a version-history feature, which should call a distinctly-named method, not a flag on the normal one.
- **User-supplied search query text is sanitized against SOSL/SOQL reserved-character injection exactly once**, at the `OI_SearchService` boundary, before any Selector or dynamic SOSL string (`OI_RecordSelector`'s `Search.query()` call, [SearchEngine.md §12](SearchEngine.md#12-record-search)) is constructed from it — a second, redundant sanitization step inside a Selector is not required and duplicating the logic there is a review flag, not a safety improvement ([SearchEngine.md §18](SearchEngine.md#18-security-and-sharing)).
- `OI_GraphRepository`'s write methods always `insert` a new version row; a `Database.update`/`Database.upsert` call against `OI_Graph_Node__c`/`OI_Graph_Edge__c` content fields is a review blocker — the only permitted in-place field updates are `Is_Current__c` (on the row being superseded, only from inside `commitVersion`) and `Last_Seen_Run__c` (on a liveness touch, only from inside `touchLiveness`), and both live inside `OI_GraphRepository` exclusively (ADR-0014, [ADR-0016](ADR/0016-repository-atomic-commit-and-optimistic-concurrency.md)).

## 5. Bulkification & Governor Limits

- Every method that can be called with more than one record must be written and tested for at least 200 records (`CLAUDE.md` §Testing Standards — "bulk tests").
- DML, callouts, and SOQL are always outside loops; batch/chunk sizes for the Metadata Scanner are configuration (`OI_Metadata_Type_Config__mdt.Batch_Size__c`), not literals, so they can be tuned per org without a deploy.
- Any code path that could exceed a governor limit at scale (heap, CPU, SOQL rows, callouts) must have its limit assumption stated in a one-line comment at the boundary where it's enforced (e.g., the chunk-size clamp) — this is the one place inline comments are expected, because the *why* (governor limit, not obvious from the code) is exactly the non-obvious-constraint case `CLAUDE.md` calls out.

## 6. Error Handling

- Throw, don't return sentinel values, for failure conditions (`null`/`-1`/empty-string-as-error is a review blocker).
- Every thrown exception is one of `OI_ApplicationException`'s subtypes (Architecture §12) — never a bare `System.Exception` or a raw platform exception (`DmlException`, `QueryException`) escaping a Service boundary; Services catch platform exceptions and re-wrap with context.
- `catch` blocks that do nothing (`catch (Exception e) {}`) are a review blocker, no exceptions.
- User-facing messages (anything reaching `AuraHandledException` or the REST error envelope) never contain: stack traces, SOQL/DML text, internal object or field API names, or org IDs.

## 7. Logging

- All logging goes through `OI_LoggerService` — no `System.debug` left in code destined for the package (it's fine transiently while developing, but a review blocker at PR time).
- Every log call includes a correlation ID; Services propagate the correlation ID they were given (from the Controller or the Scan Run) rather than minting a new one mid-chain, so a single user action or scan run is traceable end-to-end through `OI_Log__c`.

## 8. Security

- Every new `@AuraEnabled`/`@RestResource` method starts with an explicit Custom Permission check via `OI_SecurityService`, before any other logic — no exceptions, even for read-only methods.
- Any `without sharing` class requires a one-line comment stating which Architecture-doc-approved case it falls under (currently: `OI_GraphRepository`'s write paths only, as the sole writer of app-internal graph data — Architecture §14, [ADR-0012](ADR/0012-graph-repository-storage-gateway.md)) — an undocumented `without sharing` is a review blocker.
- No literal Org/User/Profile/PermissionSet/RecordType IDs anywhere in Apex, tests included (tests use dynamically-created or dynamically-queried records, never hardcoded IDs from a specific org).

## 9. Apex Class & Method Documentation

Every public class documents (per `CLAUDE.md` §Documentation Standards): purpose, responsibilities, dependencies, inputs, outputs, limitations. House style — ApexDoc-style block immediately above the class:

```
/**
 * Purpose: <one sentence>
 * Responsibilities: <bullet-ish list>
 * Dependencies: <Selectors/Repositories/Adapters/Services this class calls>
 * Limitations: <known boundary conditions, e.g. "hop depth capped at Max_Hop_Depth__c">
 */
```

Complex algorithms (graph traversal, incremental-diff checksum logic) get an inline comment at the point of the non-obvious decision explaining *why* that approach was chosen — not a restatement of the code.

## 10. LWC Standards

- **Container vs. presentational, no exceptions** ([GraphUI.md §3](GraphUI.md#3-component-architecture)): a component either calls Apex (container) or renders props/emits events (presentational) — never both. An `import` of an Apex method inside `oiGraphCanvas`, `oiGraphNode`, `oiFilterPanel`, `oiBreadcrumbTrail`, or the presentational half of `oiMiniMap` is a review blocker, the LWC-layer equivalent of the Apex-layer facade/Repository boundary rules above.
- One component per responsibility; a component that both renders and fetches-and-transforms-and-caches is a candidate for splitting (rendering vs. a plain JS utility module for transform/cache logic).
- No business logic in LWC JS beyond view-state derivation — anything that would be "business logic" if it moved server-side belongs in a Service, not a component (`CLAUDE.md` §Service Layer Rules — "LWCs should never contain business logic").
- Styling uses SLDS tokens and utilities where they can satisfy the approved contract. For Object Analyze mode, [VisualDesignSpecification.md](VisualDesignSpecification.md) is binding: custom semantic HTML and component-scoped CSS are permitted when Lightning base-component shadow DOM prevents the required appearance. Do not pierce or depend on private base-component DOM. Preserve keyboard behavior, focus visibility, contrast, and semantic labeling.
- Visual acceptance is evidence-based. At the designated reference viewport, capture the deployed real-org UI and compare it with the approved image using an overlay or perceptual diff. Jest/DOM tests and source review cannot close a visual-fidelity backlog item by themselves.
- Accessibility: every interactive graph/canvas control has a keyboard-operable equivalent and an ARIA label — required both for the product's own "keyboard navigation" commitment (`CLAUDE.md` §UI Philosophy) and for AppExchange Security/Quality review expectations.
- Cross-component messaging via LMS for non-parent/child communication only; direct `@api`/event dispatch for parent↔child — never both for the same channel (Architecture §9).

## 11. Static Resources & Third-Party Code

- Any third-party JS (e.g. a graph-rendering library) vendored as a Static Resource must be: pinned to an exact version, checked in with its license, and reviewed for CSP compliance (no `eval`, no remote script/style loading) before use — a requirement of AppExchange Security Review, not a style preference.
- No CDN-loaded scripts under any circumstance (blocked by platform CSP in Lightning contexts regardless, but also a hard security-review rule).

## 12. Testing

- Test class mirrors the class under test 1:1 (`OI_GraphBuilderTest` tests `OI_GraphBuilder`), with fakes for its Selector/Repository/Adapter dependencies (enabled by constructor or setter-based dependency injection — Architecture §2, ADR-0003). `OI_GraphEngineTest` specifically asserts the facade contains no logic of its own — every method call is verified to delegate to exactly the expected internal component (ADR-0013). `OI_SearchServiceTest` specifically asserts it never calls anything Graph-Engine-facade-internal ([SearchEngine.md §23](SearchEngine.md#23-graph-engine-integration)), the same style of "boundary is never crossed" assertion, applied to Search's own most important structural rule.
- Every test class covers: positive path, negative/permission-denied path, bulk (200-record) path, and at least one boundary condition specific to that class (e.g. hop-depth ceiling, empty-org/no-metadata case per `CLAUDE.md` §Metadata Assumptions).
- Assertions target observable behavior (returned DTO shape, thrown exception type, persisted record state) — never internal call counts/mock-verification-only tests with no behavioral assertion.
- `Test.setMock`/`HttpCalloutMock` fixtures for every Adapter test — no test may depend on a live Tooling/Metadata API callout succeeding.

## 13. Formatting & Lint (already enforced by tooling — restated for completeness)

- Prettier (`prettier-plugin-apex`, `@prettier/plugin-xml`) is the formatting source of truth; do not hand-format against it.
- ESLint (`@salesforce/eslint-config-lwc`, `@salesforce/eslint-plugin-aura`) governs LWC/Aura JS; do not disable a rule inline without a one-line justification comment.
- Husky + lint-staged run Prettier/ESLint/related-Jest-tests on every commit — a red pre-commit hook is fixed, not bypassed with `--no-verify`.

## 14. Pull Request Expectations

Every PR states, per `CLAUDE.md` §Deliverables: the architecture touched, key design decisions (and trade-offs, if any — link an ADR if the decision is significant enough to warrant one), risks, and any follow-up work identified but deferred (goes to [Backlog.md](Backlog.md), not left implicit).

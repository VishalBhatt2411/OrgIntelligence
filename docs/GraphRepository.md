# Graph Repository & Storage Layer — Salesforce Org Intelligence Platform

Status: Draft v1
Owner: Architecture
Applies to: API v67.0

This document is the complete architectural specification for `OI_GraphRepository` and the Storage Provider layer beneath it — the only part of the platform permitted to issue a storage operation against node/edge data. [GraphEngine.md §7.1](GraphEngine.md#71-graph-repository-architecture) already introduced this component at summary depth, as one of the Graph Engine facade's five internals; this document is that summary's full elaboration, and — per this round's mandate — corrects two real gaps that summary-level treatment had left unresolved (§0). It contains no implementation code — only structure, contracts, and rationale.

**Governing constraint, stated once and enforced throughout: `OI_GraphRepository` must remain completely domain-agnostic.** It knows Node, Edge, version, checksum, and storage backend. It does not know Object, Field, Flow, Apex, Report, Dashboard, or any other Salesforce metadata concept, and it never will — that knowledge belongs entirely to the Metadata Scanner ([MetadataScanner.md](MetadataScanner.md)) and `OI_MutationGenerator`, both of which sit several layers above this one and are invisible from here. The required flow is fixed:

```
OI_GraphEngine (facade)
        ↓
OI_GraphRepository
        ↓
OI_IGraphStorageProvider (interface)
        ↓
Physical Storage (Custom Objects / Big Objects / Platform Cache / future backends)
```

`OI_GraphEngine` and `OI_GraphBuilder` never access Salesforce storage directly — not a SOQL query, not a DML statement, not a `Cache.Org` call, anywhere in either class. Every read and write they need is expressed as a call into `OI_GraphRepository`.

---

## 0. Relationship to Prior Documents — What This Corrects and Adds

[GraphEngine.md §7.1](GraphEngine.md#71-graph-repository-architecture) got the shape of this layer right — the Repository/Storage Provider split, the Custom-Object/Big-Object/Platform-Cache backends, the division of labor with `OI_GraphCache`. Designing it at full depth surfaced two real gaps that a summary-level treatment had papered over, plus one inconsistency with `CLAUDE.md`'s own stated rules that had crept in unnoticed. All three are corrected here, not just described:

| Gap / inconsistency found | Where it was (silently) wrong | Correction |
|---|---|---|
| **`insertVersion` + `flipCurrent` were described as two separate Repository calls.** | [GraphEngine.md §7.1](GraphEngine.md#71-graph-repository-architecture) listed them as independent contract methods. Called separately, a failure between the two calls leaves either zero or two `Is_Current__c = true` rows for the same key — a real correctness bug, not a hypothetical one, the moment this layer is built for real. | Merged into one atomic operation, `commitVersion` (§6, §14). |
| **No enumeration query for retire-detection.** | `OI_MutationGenerator`'s retire-detection ([MetadataScanner.md §15](MetadataScanner.md#15-mutation-generation-boundary)) needs "all current Active keys for a given `typeKey`" — a bulk enumeration, not a targeted key-set lookup. [GraphEngine.md §7.1](GraphEngine.md#71-graph-repository-architecture)'s contract only had `getCurrentVersions(Set<key>)`, which requires already knowing the keys — useless for "tell me what exists so I can tell what's missing." | Added `getCurrentKeysByType` as a first-class, paginated Repository operation (§2, §13). |
| **The Selector/Repository split `CLAUDE.md` itself mandates** ("Selectors retrieve data. Repositories abstract data access where appropriate.") **was never actually applied to the Graph Engine's own reads.** | [GraphEngine.md §7.1](GraphEngine.md#71-graph-repository-architecture) implied `OI_GraphRepository` constructs its own SOQL for `getCurrentVersions`, while Backlog GE-3 separately lists `OI_NodeSelector`/`OI_EdgeSelector` doing "bulk key-set reads" — two components with an undefined division of labor between them, which is exactly the kind of ambiguity `CLAUDE.md`'s layering rules exist to prevent. | `OI_GraphRepository` does not construct SOQL itself. Every Custom-Object read it needs is delegated to `OI_NodeSelector`/`OI_EdgeSelector`; the Repository's own methods are orchestration over those Selectors plus the Storage Providers, not a SOQL-writing class in their own right (§12). |

Everything else in [GraphEngine.md §7.1](GraphEngine.md#71-graph-repository-architecture) — the Storage Provider abstraction, the three named providers, the division of labor with `OI_GraphCache` — holds and is elaborated, not contradicted, below. [ADR-0016](ADR/0016-repository-atomic-commit-and-optimistic-concurrency.md) formalizes the `commitVersion` atomicity/concurrency decision; [GraphEngine.md §7.1](GraphEngine.md#71-graph-repository-architecture) itself is amended to point here as the authoritative source and to reflect the corrected contract.

**Sprint 9 note — GE-2c implemented**: §15's retry contract below (`OI_GraphBuilder`, on
`OI_ConcurrencyException`, re-reads and retries its decision exactly once) was previously
documented but not built — `OI_GraphBuilder.ingest()` shipped in Sprint 8 without it, a
real gap this closes. One simplification from the original sketch: no jittered backoff
delay is introduced before the retry. Apex has no synchronous sleep primitive usable
mid-transaction, and a delay would need to be simulated via a second Queueable hop —
meaningfully more machinery than the narrow race window described below actually
warrants. The retry is immediate; a second conflict still propagates as a real failure,
unchanged from the original design.

---

## 1. Repository Philosophy

Three words carry this document, in order of how often they'd be violated if unstated: **domain-agnostic**, **the only writer**, **generic over what, not how**.

**Domain-agnostic** is the constraint stated at the top of this document, restated here because it is the one most easily lost in a deep persistence-layer design: every method on `OI_GraphRepository`, every field on `OI_IGraphStorageProvider`, and every parameter either takes is expressed in Node/Edge/version/checksum vocabulary. A method named `getFlowsChangedSince` would be a violation; `getCurrentKeysByType(typeKey)` is not, because `typeKey` is an opaque string the Repository never interprets.

**The only writer** means exactly what [ADR-0012](ADR/0012-graph-repository-storage-gateway.md) already decided: no other class, anywhere in the platform, issues a DML statement or a `Cache.Org` call against graph data. This document does not reopen that decision; it specifies precisely what the one writer's contract is.

**Generic over what, not how** is this layer's version of [GraphEngine.md §1](GraphEngine.md#1-graph-philosophy)'s "generic and bounded": the Repository's *public contract* (§2) is a small, fixed set of operations that never grows per backend or per domain type. *How* each operation is fulfilled is delegated one level down, per backend, to a Storage Provider (§3) — this is what keeps the Repository itself from becoming, over time, a second god-object sitting where the original "one big service" anti-pattern used to be (flagged as a risk in GraphEngine.md §21, restated and elaborated in §21 below).

---

## 2. GraphRepository Interface

`OI_GraphRepository`'s complete public contract — five operations, corrected from GraphEngine.md §7.1's list per §0 above:

| Method | Input | Output | Semantics |
|---|---|---|---|
| `getCurrentVersions` | `Set<key>` (node keys or edge keys — never mixed in one call) | `Map<key, VersionRecord>` | Bulk lookup of the *current* version for each key in the set; keys with no current version are simply absent from the result map (not an error — "doesn't exist yet" is an expected outcome, not a failure). Delegates the actual SOQL to `OI_NodeSelector`/`OI_EdgeSelector` (§12). |
| `getCurrentKeysByType` | `typeKey`, `cursor` (opaque, optional), `pageSize` | `Page<key>` (`items[]`, `nextCursor`, `hasMore`) | **New in this document.** Paginated enumeration of every currently-Active key for a given `typeKey`, scoped `Is_Current__c = true` and `State__c = 'Active'`. The sole purpose this exists for is retire-detection (§9, [MetadataScanner.md §15](MetadataScanner.md#15-mutation-generation-boundary)): `OI_MutationGenerator` pages through this to get "everything the graph currently thinks exists of this type," diffs it against what a full scan actually observed, and emits `RetireNode`/`RetireEdge` mutations for the difference. |
| `commitVersion` | `newVersionRecord`, `supersededVersionKey` (optional — absent for a brand-new key) | the inserted `VersionRecord` | **Corrected from two calls to one, per §0.** Atomically inserts `newVersionRecord` and, if `supersededVersionKey` is present, flips that row's `Is_Current__c` to `false` — both within one enforced transaction (§14). This is the *only* way a new version ever comes into existence; there is no bare `insertVersion` or bare `flipCurrent` on the public contract. |
| `touchLiveness` | `key`, `runId` | void | Updates `Last_Seen_Run__c` in place on the current row for `key` — the one narrow exception to immutability that isn't a full version creation (GraphEngine.md §2, §7). Never touches `Is_Current__c` or any content field. |
| `archiveSupersededVersions` | `cutoff` (age or count threshold) | count archived | Moves non-current version rows past the retention window — and every version row for a `Purged` key — to the Big Object provider, then removes them from the Custom Object provider (§9, §18). |

**What is deliberately not on this list**: there is no `deleteNode`/`deleteEdge` (deletion is a `State__c = SoftDeleted` new version via `commitVersion`, per GraphEngine.md §5 — the Repository has no concept of a hard delete of live data outside archival), no per-type filtering on `getCurrentVersions` (type filtering, if ever needed at the Repository boundary, is a parameter on `getCurrentKeysByType`, not a reason to add a second shape to the key-set lookup), and no direct cache-eviction method exposed to callers outside `OI_GraphCache` (§10 — cache policy is not this document's concern).

**`VersionRecord` shape** — the generic record both Node-flavored and Edge-flavored calls pass through this contract: `key`, `versionKey`, `versionNumber`, `typeKey`, `label`, `secondaryKey`, `attributes`, `checksum`, `state`, `graphScope`, `firstSeenRunId`, `lastSeenRunId`, `isCurrent`, plus two **optional** fields present only when the record is edge-flavored: `sourceKey`, `targetKey`. This is a deliberate simplification over having entirely separate `NodeVersionRecord`/`EdgeVersionRecord` shapes with duplicated method families (`getCurrentNodeVersions` / `getCurrentEdgeVersions`, etc.) — see §23 for why this was chosen over the alternative and why it does not contradict `OI_Node`/`OI_Edge` remaining distinct types one layer up, in the Graph Engine's own domain model (GraphEngine.md §2–§3).

---

## 3. StorageProvider Interface

`OI_IGraphStorageProvider` is the interface every backend implements; `OI_GraphRepository` holds one instance per backend and dispatches to it, never branching on backend type inline (that would be the exact Open/Closed violation [ADR-0012](ADR/0012-graph-repository-storage-gateway.md) exists to prevent).

| Method | Called by (Repository operation) | Notes |
|---|---|---|
| `readCurrent(keys)` | `getCurrentVersions` | Only the Custom Object provider implements this meaningfully in the interactive path; Big Object/Platform Cache providers are never asked for "current" (§8–§10). |
| `readCurrentKeysByType(typeKey, cursor, pageSize)` | `getCurrentKeysByType` | Custom Object provider only (§9). |
| `writeVersion(record, isNew)` | `commitVersion` | `isNew` distinguishes "insert version 1" from "insert version N, superseding one" purely for provider-side logging/metrics — the DML shape (an `insert`, always) is identical either way. |
| `markSuperseded(versionKey)` | `commitVersion` | Sets `Is_Current__c = false` on exactly one row; called by the Repository within the same transaction as `writeVersion` above, never independently. |
| `touchLiveness(key, runId)` | `touchLiveness` | |
| `moveToArchive(records)` | `archiveSupersededVersions` | Only meaningful for providers that have both a "live" and an "archive" side (Custom Object → Big Object); the Platform Cache provider does not implement this (cache entries simply expire, §10). |

**Three concrete implementations** (unchanged in identity from GraphEngine.md §7.1, elaborated in §8–§10 below):

| Provider | Backend | Implements |
|---|---|---|
| `OI_CustomObjectStorageProvider` | `OI_Graph_Node__c` / `OI_Graph_Edge__c` | All six methods above |
| `OI_BigObjectStorageProvider` | `OI_Graph_Node_Archive__b` / `OI_Graph_Edge_Archive__b` | `writeVersion` (append-only) and a read path used only by future history features (§9) — never `readCurrent`, `markSuperseded`, or `touchLiveness`, since archived rows are, by definition, no longer current or live |
| `OI_PlatformCacheStorageProvider` | Platform Cache (Org partition) | A narrower shape entirely — `get(key)`/`put(key, value, ttl)`/`evict(key)`, not the six-method interface above; it exists to back `OI_GraphCache`'s policy layer, not to participate in version commit at all (§10) |

The Platform Cache provider's divergent shape is intentional, not an inconsistency: it is not part of the durable version-commit path (§6) at all, and forcing it to implement `writeVersion`/`markSuperseded` methods it has no meaningful behavior for would be exactly the kind of interface pollution good interface design avoids. It implements a second, smaller interface (`OI_IKeyValueCacheProvider`) that `OI_IGraphStorageProvider` does not require.

**Future providers** (a hypothetical native Salesforce graph primitive, or an External Object-backed provider for a future integration) implement `OI_IGraphStorageProvider` the same way `OI_CustomObjectStorageProvider` does today — zero change to `OI_GraphRepository`, `OI_GraphBuilder`, or anything above them (§25).

---

## 4. Node Persistence

A node version, at the Repository boundary, is a `VersionRecord` (§2) with no `sourceKey`/`targetKey`. `OI_CustomObjectStorageProvider.writeVersion` maps it onto `OI_Graph_Node__c` exactly as [DataModel.md §2.3](DataModel.md#23-oi_graph_nodec) specifies: `key → Node_Key__c`, `versionKey → Node_Version_Key__c` (the External ID / insert-uniqueness field), `versionNumber → Version_Number__c`, `typeKey → Node_Type__c`, and so on, field-for-field. The Repository itself never references `Node_Key__c`/`Node_Type__c`/etc. by name — those are the Custom Object provider's private mapping detail; the Repository's own method signatures and the `VersionRecord` shape are backend-agnostic (§0's Selector-delegation correction applies equally here: the provider owns the field-name mapping, the Repository owns none of it).

Node-specific behavior at this layer is minimal by design — nodes carry no structural constraint beyond the generic `VersionRecord` fields, unlike edges (§5). This asymmetry is intentional and is why the two are still worth keeping notionally distinct even under a shared `VersionRecord` shape (§23): an edge is a node-plus-two-references; a node is not a lesser edge.

---

## 5. Edge Persistence

An edge version is a `VersionRecord` with `sourceKey`/`targetKey` populated. `OI_CustomObjectStorageProvider.writeVersion`, when handed an edge-flavored record, maps onto `OI_Graph_Edge__c` per [DataModel.md §2.4](DataModel.md#24-oi_graph_edgec): `sourceKey → Source_Node_Key__c`, `targetKey → Target_Node_Key__c` — both **references to the logical node key, never a `Node_Version_Key__c`**, restated here because it is a Repository-layer invariant, not just a Graph Engine domain-model choice: the Repository never rejects, and never needs to validate, an edge whose endpoint node has no current version yet (out-of-order scan writes, GraphEngine.md §3/§6) — endpoint existence is not this layer's concern; it is a `OI_LoggerService`-observed dangling-edge sweep concern, entirely upstream of storage.

**Why the Repository provider dispatches on record "flavor" (node vs. edge) rather than on a Salesforce-specific type check**: the dispatch condition is exactly "does this `VersionRecord` have `sourceKey`/`targetKey` populated," which is graph-theory vocabulary (an edge is defined by having two endpoints; a node is not), not Salesforce vocabulary — preserving domain-agnosticism (§1) while still allowing one write path to correctly target `OI_Graph_Node__c` vs. `OI_Graph_Edge__c` underneath.

---

## 6. Version Persistence — the `commitVersion` Atomicity Fix

This is the section that exists because of the gap identified in §0, and it deserves to be walked through explicitly rather than left as a one-line contract entry, because the failure mode it prevents is a genuine data-integrity bug, not a theoretical one.

**The naive design** (as GraphEngine.md §7.1 described it before this document): the Builder calls `insertVersion(newRow)`, then separately calls `flipCurrent(nodeKey, oldVersionKey)`. If the transaction succeeds fully, this works. But Apex governor-limit exceptions, unhandled callout timeouts inside the *same* transaction (rare but possible if a caller does something ill-advised between the two calls), or simply a defensive coding mistake that lets an exception propagate between the two statements, leave the row set in a state where **either zero or two rows have `Is_Current__c = true`** for the same `Node_Key__c`/`Edge_Key__c`. Both outcomes are silently wrong: zero-current makes the node invisible to every read path that filters `Is_Current__c = true` (§12, effectively a phantom soft-delete); two-current makes `getCurrentVersions` return an ambiguous result and breaks the "exactly one current row per key" invariant every other section of this document (and GraphEngine.md) assumes holds.

**The fix**: `commitVersion` is one Repository method, and its implementation performs both DML operations — the insert of the new row and the update of the superseded row's `Is_Current__c` flag — inside a single `Database.transaction`-scoped unit with a `Savepoint` taken immediately before either operation. If the insert succeeds but the flip fails (or vice versa), the Repository rolls back to the savepoint and re-throws, so the caller (`OI_GraphBuilder`) sees a clean failure — no partial state, no silent corruption — rather than a half-committed pair of DML statements. This is not a new Salesforce capability being invented; `Savepoint`/`Database.rollback` are ordinary platform primitives — the fix is architectural (never expose the two steps as separately callable), not technical.

**Ordering, stated precisely**: insert-then-flip, never flip-then-insert. Inserting first means that if the insert itself fails (e.g., a validation rule, a duplicate `Node_Version_Key__c` from a concurrency conflict — §15), the old row's `Is_Current__c` was never touched, and no rollback is even needed for that failure mode — it's a clean no-op from the caller's perspective. Flip-then-insert would briefly leave zero current rows if the insert step then failed, which is strictly worse.

**Brand-new keys skip the flip half entirely** — `supersededVersionKey` is simply absent, and `commitVersion` performs only the insert, with no savepoint/rollback machinery needed (there is nothing to roll back to that could be left inconsistent).

---

## 7. Current-Version Resolution

"What is the current version of key K" is answered exactly one way, everywhere in the platform: `Is_Current__c = true AND {Node_Key__c | Edge_Key__c} = K`. There is deliberately no second mechanism (e.g., "highest `Version_Number__c`") — computing "current" by taking a `MAX()` would work *most* of the time but silently produce the wrong answer the moment a version is ever inserted out of numeric order (which §15's optimistic-retry path can legitimately cause under conflict), whereas the flag is authoritative by construction: `commitVersion` (§6) is the only place it is ever set, and it enforces the invariant directly rather than deriving it.

**Invariant**: exactly one `Is_Current__c = true` row exists per logical key at any time, except for the brief window *inside* a `commitVersion` transaction between the insert and the flip (invisible to any other transaction, since Salesforce transactions are isolated) and the (impossible-in-normal-operation, detectable) case covered next.

**Self-healing is deliberately not built for a violated invariant.** If the invariant is ever found violated in practice (e.g., discovered by an audit query, or by a defensive assertion inside `getCurrentVersions` that notices more than one current row for a requested key), the Repository logs an `OI_LoggerService` `ERROR` with both offending `Node_Version_Key__c`s and returns the *most recently inserted* row as a best-effort answer rather than silently picking one, silently merging, or attempting an automatic repair DML. Automatic repair was considered and rejected (§23) — a bug that corrupts this invariant is a code defect worth surfacing loudly and fixing at the source, not a runtime condition to paper over with more logic in the read path.

---

## 8. Custom Object Storage

`OI_CustomObjectStorageProvider` is the interactive, synchronous-SOQL backend — the one every read on the hot path (Traversal, Search, Detail Panel) ultimately reaches, always through `OI_NodeSelector`/`OI_EdgeSelector` (§12), never through a query the provider or Repository writes inline.

- **Write shape**: always `insert` for new version rows (never `update`/`upsert` against content fields — CodingStandards §4's existing rule, restated here as this document's own hard constraint), and exactly one `update` per `commitVersion` call for the single superseded row's `Is_Current__c` flip.
- **Bulk shape**: every provider method accepts a list, never a single record — a single-record call is simply a one-element bulk call, with no separate code path (§11).
- **Field mapping ownership**: the provider is the only class that knows `VersionRecord.key` maps to `Node_Key__c` (vs. `Edge_Key__c` for an edge-flavored record) — this mapping knowledge does not leak into `OI_GraphRepository` or anything above it (§4/§5).
- **Read delegation**: the provider itself does not construct SOQL for `readCurrent`/`readCurrentKeysByType` — it calls `OI_NodeSelector`/`OI_EdgeSelector` (§12), keeping query construction concentrated in the one class type (`*Selector`) `CLAUDE.md` and CodingStandards §4 already designate for that responsibility.

---

## 9. Big Object Archival

`OI_BigObjectStorageProvider` implements only the write-and-occasionally-read-back half of the interface — `writeVersion` (append-only, called by the scheduled archival job, never by `commitVersion` directly — see below) and a read path reserved for a future "show history" feature (GraphEngine.md §19/§20), never `readCurrent`/`markSuperseded`/`touchLiveness`, which have no meaning for archived data.

**Who triggers archival, and when**: `archiveSupersededVersions` (§2) is called by a scheduled batch job (`OI_GraphArchivalBatch`, named here for the first time — Backlog should track it under GE-7), never inline inside `commitVersion`. This is a deliberate ordering choice: archiving synchronously as part of every version-commit would tie an interactive-path Custom Object write to a Big Object DML operation in the same transaction, adding latency and a second class of failure mode to every scan write, for a benefit (immediate archival) nothing on the interactive path actually needs. Archival is eventually-consistent by design — a superseded row sits in the live Custom Object table for some bounded window before the batch job sweeps it, and every read path already filters `Is_Current__c = true`, so a not-yet-archived superseded row is invisible to every normal read regardless (§7) — its continued physical presence in the live table costs storage, not correctness.

**Big Object constraints this provider must respect** (restated from ADR-0002, made concrete here): no standard DML (`Database.insertImmediate` only), index fields must be declared upfront in the Big Object's metadata and cannot be added later without a new Big Object, and reads are async-query-only (`SOQL` against a Big Object executes but without the synchronous-consistency guarantee a Custom Object query has) — acceptable because, per §7's invariant discussion, nothing on any interactive path ever reads from this provider.

**Retire-detection's `getCurrentKeysByType` never touches this provider** — it is exclusively a Custom Object provider operation (§2, §8); by the time a version is archived it is, by definition, not current, so it was never a candidate for retire-detection's "what does the graph currently think exists" question in the first place.

---

## 10. Platform Cache Interaction

Restated precisely from GraphEngine.md §7.1/§14, because the division of labor here is easy to get backward: **`OI_GraphRepository`'s `OI_PlatformCacheStorageProvider` is the only component with direct Platform Cache API access** (`Cache.Org.get`/`put`/`remove`). `OI_GraphCache` — the facade-internal policy component (GraphEngine.md §14) — never calls the Platform Cache API itself; it decides keys, TTLs, and invalidation triggers, and issues its actual reads/writes *through* this provider, exactly the way `OI_GraphTraversal` issues its durable reads through the Custom Object path (§8/§12).

**Why this provider does not implement `OI_IGraphStorageProvider`'s full six-method shape** (§3): it has no notion of "current version" (a cache entry is either present or absent, with a TTL — there is no versioning concept at this layer at all) and no notion of archival (an evicted or expired cache entry simply ceases to exist; nothing is preserved). Forcing it into the same interface as the two durable providers would mean either throwing `UnsupportedOperationException`-style stubs for four of six methods, or quietly implementing them as no-ops — both are worse than giving it the smaller, honest interface (`OI_IKeyValueCacheProvider`) it actually needs.

**What the Repository is responsible for here, concretely**: exposing `get(key)`/`put(key, value, ttl)`/`evict(key)` as thin pass-throughs to this provider, callable only by `OI_GraphCache` (never by `OI_GraphBuilder`/`OI_GraphTraversal`, which have no reason to touch the cache directly and would bypass `OI_GraphCache`'s policy layer if they did) — a facade-internal-to-facade-internal access rule, enforced the same way as every other internal boundary in this platform: naming convention plus code review (CodingStandards §2).

---

## 11. Bulk Operations

Every method on `OI_GraphRepository` and `OI_IGraphStorageProvider` is bulk-shaped by contract, not by convention — there is no single-key overload that internally loops and issues N separate DML/query operations; a single-key call is simply a one-element list passed to the same bulk method (CodingStandards §4's "no SOQL in a loop" rule, applied one level deeper: no *Repository call* in a loop either, inside `OI_GraphBuilder`'s own batch-processing code).

**The Builder's batch shape drives this directly** (GraphEngine.md §7): for one incoming Mutation batch, the Builder issues exactly one `getCurrentVersions` call for the whole batch's key set, partitions the results into new/liveness-touch/new-version buckets, then issues one bulk `touchLiveness` call for the liveness bucket and one `commitVersion` call **per key** in the new-version bucket (not bulk, by necessity — §14 explains why version-commit cannot itself be bulked across keys the way a plain insert can, without giving up the atomicity guarantee §6 exists to provide) — chunked to respect governor limits (heap/CPU/DML-statement-count) the same way `OI_Metadata_Type_Config__mdt.Batch_Size__c` already chunks scan batches (Architecture §17).

**`getCurrentKeysByType`'s pagination (§13) exists precisely because this operation cannot be bulk-shaped the normal way** — there is no bounded key set to pass in; the whole point is enumerating an unbounded (or at least unknown-in-advance) set, which is what pagination is for rather than a single unbounded bulk call.

---

## 12. Query Strategy — Selector Delegation

This section formalizes the correction identified in §0: `OI_GraphRepository` does not write SOQL. `OI_NodeSelector` and `OI_EdgeSelector` do — consistent with `CLAUDE.md`'s own explicit rule ("Selectors retrieve data. Repositories abstract data access where appropriate."), which this platform had been correctly applying everywhere *except*, until now, inside its own most complex Repository.

**Division of responsibility**:

- `OI_NodeSelector`/`OI_EdgeSelector` own: query construction, the `WHERE Is_Current__c = true` predicate centralization (CodingStandards §4, GraphEngine.md §13/§15/§21), field-list discipline (explicit fields only, no unbounded pulls), and index-aware `WHERE`-clause shaping (e.g., leading with `Node_Key__c IN :keys` before any secondary filter, so the query planner has a selective predicate to start from).
- `OI_GraphRepository` owns: which Selector method to call for which of its own five operations (§2), orchestrating the result into a `VersionRecord`-shaped response, and — critically — everything the Selector *cannot* do: writes (Selectors are read-only by convention, CodingStandards §2), cross-backend orchestration (a `getCurrentVersions` call that needs to check Custom Object *and* eventually a hypothetical faster-path cache would live here, not in a Selector), and the atomicity/concurrency guarantees of §6/§15.

**Concretely**: `OI_GraphRepository.getCurrentVersions(keys)` calls `OI_NodeSelector.selectCurrentByKeys(keys)` (or the Edge equivalent), which returns `OI_Graph_Node__c` rows (or a thin projection), and the Repository maps those rows into the generic `VersionRecord` shape (§2) before returning — this mapping step is where "Custom-Object-field-name knowledge" and "generic Repository contract" meet, and it is the Repository's job, not the Selector's (a Selector returning a `VersionRecord` directly would leak Repository-layer modeling decisions into the Data Access layer's read-only concern, backward from how CLAUDE.md's layering is meant to compose).

**`getCurrentKeysByType`** similarly delegates to a new Selector method, `selectCurrentKeysByType(typeKey, cursor, pageSize)` — a bulk key-only projection (no `Attributes_Json__c`, no `Label__c` — retire-detection needs keys, nothing else, and CodingStandards §4's "explicit field lists only, exactly what the contract needs" rule applies here as much as anywhere).

This correction has one concrete downstream effect worth flagging now rather than discovering later: **`OI_NodeSelector`/`OI_EdgeSelector` (Backlog GE-3) become a dependency of `OI_GraphRepository` (GE-2a), not a peer built afterward for Traversal's benefit alone** — Backlog is updated accordingly (§ this round's Backlog changes).

---

## 13. Pagination

Two independent pagination surfaces exist at this layer, and they are not the same mechanism:

1. **`getCurrentKeysByType`'s cursor** (§2, §9, §12) — an opaque cursor encoding the last-seen `Node_Version_Key__c`/`Edge_Version_Key__c` (keyset pagination, not `OFFSET`-based — `OFFSET` degrades on large result sets and Salesforce SOQL doesn't support it efficiently at scale regardless), consumed by `OI_MutationGenerator` in a loop until `hasMore = false`. Page size defaults to a configurable value (a new `Repository_Page_Size__c` field on `OI_Settings__mdt`, added by this document — see §DataModel changes below) rather than a literal, per the platform's existing "no hardcoded chunk sizes" convention (Architecture §17, CodingStandards §5).
2. **Client-facing pagination** (`getGraphFragment`'s `nextCursor`, API.md §2.1) is a *different* mechanism, owned by `OI_GraphTraversal`/`OI_GraphSerializer`, operating over already-fetched, already-bounded fragment data — it is not this layer's concern and this document does not redefine it. The two pagination surfaces are mentioned together only to be clear they don't share a cursor format or a code path.

---

## 14. Transaction Boundaries

- **`commitVersion` is one transaction, full stop** (§6) — the insert and the flip either both apply or neither does, enforced via `Savepoint`/rollback, never exposed as two independently-committable steps.
- **A Builder batch commits at `OI_Scan_Task__c` granularity** (matching Architecture §6/GraphEngine.md §7's existing failure-isolation model) — one metadata type's mutation batch is one logical unit of work; a failure partway through fails that task (and is retried per §11's retry semantics, MetadataScanner.md §11), without rolling back or otherwise affecting a different type's already-committed writes from the same scan run. This means a single scan run can legitimately end with some types' writes committed and others not — an accepted consequence of per-type failure isolation, not a bug (Architecture §6).
- **`touchLiveness` and `commitVersion` for different keys within one batch are independent transactions** at the granularity Apex naturally provides per top-level batch chunk (governed by the same chunking §11 already describes) — there is no requirement that an entire scan task's worth of writes succeed or fail as one atomic unit; only a single key's version-commit needs that guarantee, and §6 already provides exactly that, no more.

---

## 15. Concurrency Handling

This is new design content — neither GraphEngine.md nor any existing ADR addressed what happens when two writers touch the same key concurrently, and Architecture §17 already commits the platform to **horizontal scan parallelization** ("independent metadata types can scan concurrently via separate Queueable chains"), which makes this a real scenario, not a hypothetical one: two concurrently-running Queueable chains could, in principle, both produce a mutation touching the same node key in the same narrow time window (e.g., a cross-reference discovered by two different scanner types pointing at the same target).

**Why pessimistic locking (`SELECT ... FOR UPDATE`) does not actually solve this**: Salesforce row locks acquired via `FOR UPDATE` are held only for the duration of the *current transaction*. Two concurrent Queueable executions are two separate transactions; the first one's lock is released the instant its transaction commits, well before the second transaction's `commitVersion` call runs its own read. `FOR UPDATE` protects against a race *within* a single transaction's own bulk operation (irrelevant here — a single transaction processes its own batch's keys sequentially in memory before issuing DML) but provides no cross-transaction mutual exclusion at all. Relying on it here would be a design that looks correct in review and fails silently in production under real concurrent load — worth stating explicitly rather than reaching for the platform's most familiar-sounding locking primitive and assuming it applies.

**The actual mechanism: optimistic concurrency via the deterministic `Node_Version_Key__c`/`Edge_Version_Key__c` External ID.** Recall `versionKey = hash(key + versionNumber)` (GraphEngine.md §2). If two concurrent transactions both read "current version is N, checksum differs, I need to insert version N+1" for the same key, both compute the *same* `versionKey` for their respective "version N+1" insert. Salesforce's own External ID uniqueness constraint means the second insert to actually execute fails with a `DUPLICATE_VALUE` `DmlException` — the platform itself detects the conflict; no custom locking code is needed to discover it.

**Conflict resolution, once detected**: `OI_GraphRepository.commitVersion` catches the specific `DUPLICATE_VALUE` failure mode on its insert step (distinguishing it from any other `DmlException` cause, which is re-thrown unchanged — a validation-rule failure, for instance, is a real error, not a conflict to retry past) and re-throws a dedicated `OI_ConcurrencyException` (new — see Architecture.md change below) rather than the raw platform exception, so `OI_GraphBuilder` has a typed signal to act on rather than string-matching an error message. `OI_GraphBuilder`, on catching `OI_ConcurrencyException` for a given key, re-reads that key's current version (a fresh `getCurrentVersions` call — the other transaction's commit is now visible) and retries its own three-way decision (GraphEngine.md §7) exactly once more with a small jittered backoff before surfacing a task-level failure if the second attempt also conflicts (which, for a two-way race, it should not — a third writer racing the same key at the same instant is vanishingly unlikely given how narrow the actual write window is, and is not engineered against further; see §21).

**This is deliberately cheap in the overwhelmingly common case**: no lock is acquired, no extra read happens, and no retry logic executes at all unless a genuine concurrent write to the *same key* actually lands in the same narrow window — which, given that most nodes are touched by exactly one scanner type, is rare. The cost of this design is paid only when the race it protects against is real.

---

## 16. Idempotency

A retried Queueable hop (governor-limit exception mid-transaction, transient platform error, or MetadataScanner.md §11's retry strategy re-enqueuing a failed task) may replay an identical mutation batch. Two cases, both already handled by mechanisms this document and GraphEngine.md already establish, worth naming as idempotency properties explicitly rather than leaving them as an implicit side effect:

- **Replaying a liveness touch** is a pure no-op past the first — `touchLiveness` unconditionally sets `Last_Seen_Run__c` to the given `runId`; setting the same value twice has no observable difference from setting it once (GraphEngine.md §7 already states this).
- **Replaying a version-commit for content that hasn't actually changed** since the failed attempt is caught by the *same* `DUPLICATE_VALUE` mechanism §15 designed for concurrency — a retried insert of "version N+1 with the same computed `versionKey`" collides with the *successfully-committed* row from the attempt before the failure, if that attempt actually got far enough to commit before the surrounding transaction reported failure. `OI_GraphBuilder`'s retry handler (§15) treats this identically to a genuine conflict: re-read current, recompute the decision — and on re-read it will now see its own prior write as current with a matching checksum, correctly resolving to "liveness touch, nothing further to do" rather than attempting a duplicate insert a second time. **The same detection path that provides concurrency safety also provides idempotency for free** — a deliberate design synergy, not a coincidence, and worth stating as such because it means idempotency did not require separate machinery (no dedup table, no "have I processed this mutation before" tracking) on top of what §15 already builds.

---

## 17. Error Handling

- `OI_ConcurrencyException` (new, `extends OI_ServiceException` — Architecture §12's hierarchy gains this one addition) signals a detected write conflict (§15) and is the only exception type `OI_GraphBuilder` is expected to specifically catch-and-retry; every other exception surfacing from `OI_GraphRepository` propagates per the platform's existing rule (Architecture §12: caught at the Service/Controller boundary, logged with correlation, translated to a sanitized user message, never swallowed).
- A Big Object write failure (`§9`) inside the scheduled archival batch is recorded on the batch's own execution log via `OI_LoggerService` and does **not** roll back or otherwise affect the live-table row it was attempting to archive — a failed archival attempt simply leaves the row live for the next scheduled run to retry; archival failure is never allowed to threaten current-graph correctness (consistent with §9's "archival is eventually-consistent, correctness never depends on it having run" framing).
- Platform Cache provider failures (a `Cache.Org` call throwing, e.g., due to partition capacity) are caught inside `OI_PlatformCacheStorageProvider` and treated as a cache miss, never propagated as an error to `OI_GraphCache` or beyond — a cache is, by definition, allowed to fail without the read path failing (it falls through to the durable Repository read instead, per GraphEngine.md §14's existing L1-miss behavior).

---

## 18. Data Retention

- **Superseded (non-current) version rows**: archived on a schedule (§9), threshold configurable (GraphEngine.md §24's still-open question on exact trigger — age vs. keep-last-N — is not resolved by this document either; it remains an open question, §24 below, not silently decided here just because this is a deeper document).
- **Purged nodes/edges**: every version row for a `SoftDeleted` key past the retention grace period moves to the archive in full (DataModel §7) — the Repository's `archiveSupersededVersions` operation covers this case identically to the "still-Active-but-superseded" case; the archival job does not distinguish the two at the Repository-contract level (both are "non-current rows past a threshold"), only at the level of which threshold config applies.
- **Archive retention itself**: Big Objects have no platform-enforced expiry — archived rows persist indefinitely unless a future feature explicitly purges them. This is an accepted, intentional choice (history has value; Big Object storage is not counted against the transactional limits this platform is protecting, ADR-0002) but is worth stating plainly rather than leaving "does the archive itself ever shrink" unanswered — currently, no.

---

## 19. Indexing Strategy

Consolidated from DataModel.md, restated here through the lens of which index each Repository/Selector operation actually depends on:

| Operation | Index relied on | Note |
|---|---|---|
| `getCurrentVersions` | `{Node\|Edge}_Key__c` (indexed, no longer unique) combined with `Is_Current__c` (indexed) | Selector query leads with the key-set predicate (highly selective), `Is_Current__c = true` narrows further — DataModel §2.3 already flags this combination as the expected index usage pattern |
| `getCurrentKeysByType` | `Node_Type__c`/`Edge_Type__c` (Text, no automatic Picklist indexing — ADR-0011) combined with `Is_Current__c` | This is the one Repository operation that queries by type *without* an accompanying key-set predicate — exactly the scenario DataModel §2.3's indexing note flagged as the case to watch if profiling ever shows `Node_Type__c` insufficiently selective alone. If a specific `typeKey` turns out to have a very large Active population and this query underperforms, a Salesforce Support custom index request against `Node_Type__c` (already flagged as a low-risk follow-up, ADR-0011) is the lever — not a Repository-layer redesign. |
| `commitVersion`'s insert | `{Node\|Edge}_Version_Key__c` (External ID, unique) | This is what makes the `DUPLICATE_VALUE` conflict-detection mechanism (§15) work at all — the uniqueness constraint is doing real architectural work, not just enforcing tidy data. |
| `archiveSupersededVersions` | `Is_Current__c` combined with an age/count threshold — no dedicated field for "candidate for archival" | Deliberately not adding a denormalized `Superseded_At__c` timestamp purely for this query's benefit was considered and rejected in favor of deriving the threshold from `Last_Seen_Run__c`/`First_Seen_Run__c` lookups to `OI_Scan_Run__c.Completed_At__c` — avoids one more mutable-in-place field beyond the two already-narrow exceptions (§2's `VersionRecord` fields), at the cost of one extra join in the archival query, which runs on a schedule, not the interactive path, so the cost is acceptable. |

---

## 20. Security and Sharing

Nothing here changes Architecture §14's decision — it is restated precisely because "the Repository" is the exact class that decision names, and this document is where a reader looking for the full justification should land:

- `OI_GraphRepository`'s write paths (`commitVersion`, `touchLiveness`, `archiveSupersededVersions`) run `without sharing`, documented per CodingStandards §8's requirement (a one-line comment stating the ADR-0012/Architecture-§14-approved justification) — these are application-internal records with no end-user-meaningful owner-based sharing model (ADR-0006).
- Every read path this Repository exposes that is reachable, even indirectly, from a Controller (i.e., everything reached via `OI_GraphTraversal`/`OI_GraphEngine`) still requires the calling Service/Controller to have already checked the relevant Custom Permission (`OI_View_Graph`) *before* reaching this layer — the Repository itself performs no permission check of its own, by design: permission gating is a Controller-boundary concern (Architecture §14, CodingStandards §8), and duplicating it here would be redundant, not defense-in-depth, since nothing outside the facade can reach this class at all (ADR-0013's facade rule makes this layer unreachable except through a path that has already gated access).
- No customer business data ever flows through this layer — every field on every `VersionRecord` is either engine-owned infrastructure (versioning/lifecycle bookkeeping) or domain-supplied opaque content (`attributes`, populated by `OI_MutationGenerator` from Salesforce *metadata*, not business records) — the CRUD/FLS considerations that apply to customer data selectors (WITH USER_MODE, CodingStandards §4) do not apply here, consistent with ADR-0006's framing of `OI_*__c` objects as application-internal.

---

## 21. Package/Upgrade Considerations

- **Schema evolution across package versions**: a future package version adding a field to `OI_Graph_Node__c`/`OI_Graph_Edge__c` (e.g., a promoted-attribute slot, GraphEngine.md §2/§20) is additive-only from this layer's perspective — `VersionRecord` gains an optional field, `OI_CustomObjectStorageProvider`'s mapping is extended, and every existing row (which simply lacks a value for the new field) remains valid and readable without a data migration. This is a direct benefit of the schemaless `Attributes_Json__c` design (GraphEngine.md §2) extending naturally to structural schema growth too.
- **Storage Provider interface evolution**: adding a method to `OI_IGraphStorageProvider` (a genuinely rare event, given the deliberately minimal five/six-operation contract, §2/§3) requires every existing provider implementation to be updated in the same package version — this is the one place interface changes are *not* free, and is exactly why §2/§3's contracts are designed to be as stable and minimal as they are; a provider interface is the single highest-blast-radius surface in this document.
- **Upgrade safety for in-flight scans**: a scan run (and its Queueable chain) spanning a package upgrade boundary is not a scenario this layer specially guards against — Salesforce package upgrades already require careful timing around running async jobs at the platform level, and `OI_Scan_Run__c`'s existing status tracking (Failed/CompletedWithErrors) is sufficient to surface a run that was interrupted by an upgrade, without this document inventing a bespoke "upgrade-aware" transaction mode.
- **No destructive schema changes ship without a documented data-migration path** — per `CLAUDE.md`'s package-compatibility rules generally; concretely for this layer, a field *rename* (as already happened once, `Api_Name__c → Secondary_Key__c`, GraphEngine.md §0 Round 1) must ship as add-new-field + dual-read/backfill + remove-old-field across multiple package versions, never a single-version rename, since existing subscriber orgs have live data in the old field.

---

## 22. Storage Migration Strategy

New design content: the entire reason a Storage Provider abstraction exists (§3, ADR-0012) is to make backend changes possible without touching callers — but "possible in principle" and "safe to actually execute against a subscriber org's live data" are different claims, and this document commits to the latter with a concrete pattern rather than leaving it implicit.

**Pattern: dual-write, verify, cutover, decommission** — for introducing a *new* provider intended to eventually replace or sit alongside an existing one for some subset of data:

1. **Dual-write phase**: `OI_GraphRepository`'s `commitVersion`/`touchLiveness` write to both the existing provider and the new one, gated by a routing flag (`OI_Settings__mdt.Storage_Migration_Mode__c`, new — a Picklist: `Off`/`DualWrite`/`ReadNew`/`NewOnly`, engine-owned infrastructure vocabulary, not a domain concept, so a Picklist is appropriate here per ADR-0011's own distinction). Reads continue against the existing provider throughout this phase — the new provider is being populated, not yet trusted.
2. **Verify phase**: an offline/batch checksum comparison (reusing the same `Checksum__c` field every version row already carries — no new comparison mechanism needed) confirms the new provider's data matches the existing provider's for a sample, then the full population, before any read traffic moves.
3. **Cutover (`ReadNew`)**: reads switch to the new provider; writes continue dual-write for a bake-in window, so a rollback to `DualWrite`-read-old remains cheap if the new provider misbehaves under real read load.
4. **Decommission (`NewOnly`)**: writes stop targeting the old provider; the old backend's data is either left in place (cheapest, if storage cost is negligible) or explicitly archived/removed in a subsequent, separately-planned step — this document does not prescribe which, since that choice depends entirely on which two backends are involved in a migration that, as of this writing, is hypothetical.

**This pattern is deliberately not built now** — no `Storage_Migration_Mode__c` field ships in v1, no dual-write code path exists yet. It is documented here as the committed *approach* for whenever a real migration need arises (a new backend replacing Custom Objects for the current-version table, for instance, if a future Salesforce platform capability made that attractive), so that when that day comes, the Storage Provider abstraction's payoff is a known, pre-agreed procedure rather than a from-scratch design exercise under time pressure. This is an extension point (§25), not a Backlog item.

---

## 23. Testing Strategy

- **`OI_GraphRepositoryTest`** (per CodingStandards §12's one-test-class-per-class-under-test rule) is tested against **fake `OI_IGraphStorageProvider` implementations**, not real Custom Object/Big Object DML — this is what makes it practical to unit-test the `commitVersion` atomicity/rollback logic (§6) and the `DUPLICATE_VALUE`-conflict-to-`OI_ConcurrencyException` translation (§15, §17) deterministically, including failure injection scenarios a real DML call can't reliably reproduce on demand (e.g., "the insert succeeds but the flip throws").
- **A shared Storage Provider contract test suite** (parallel to [MetadataScanner.md §17](MetadataScanner.md#17-package-compatibility)'s Adapter contract-test-suite pattern, and tracked the same way in Backlog under PK-4's existing scope) — any class implementing `OI_IGraphStorageProvider` must pass the same behavioral test suite (read-your-writes, bulk shape, the six-method contract's exact semantics), so `OI_BigObjectStorageProvider`, `OI_CustomObjectStorageProvider`, and any future provider are provably interchangeable at the contract level, not just by inspection.
- **Concurrency test scenario, specifically**: a test that simulates two near-simultaneous `commitVersion` calls for the same key computing the same `versionKey` (achievable in a test context by directly attempting two inserts with an identical External ID against a fake provider configured to reject the second one, mirroring the real platform's `DUPLICATE_VALUE` behavior) and asserts the retry-and-resolve path (§15) converges correctly rather than double-applying or losing an update.
- **Bulk tests**: every operation tested at 200+ keys (CodingStandards §5), including `getCurrentKeysByType`'s pagination boundary (exactly-page-size, one-more-than-page-size, zero-results cases — §13).
- **Boundary conditions specific to this layer**: brand-new key (no superseded version to flip), a key whose current version is being superseded for the first time, an edge whose endpoint node has no current version at all (§5's explicit non-validation), and the self-healing-is-not-built assertion from §7 (a test confirming the Repository logs and returns a best-effort answer rather than throwing or auto-repairing when handed a fixture with a deliberately-duplicated `Is_Current__c` state).

---

## 24. Performance Considerations

Consolidated, each item traceable to a section above:

- One bulk `getCurrentVersions`/`getCurrentKeysByType` read per Builder batch or per Mutation Generator retire-detection pass — never per-key (§11, §12).
- `commitVersion` cannot be bulked across keys the way a plain insert can (§11) — each key's insert-then-flip pair is its own transaction-scoped unit (§6, §14); at very high per-scan change volume, this is the layer's dominant cost driver, and is called out honestly here rather than only in §21/§22 of GraphEngine.md, since it is this document's own design, not just an inherited one.
- The optimistic-retry path (§15) adds cost *only* under genuine concurrent-write contention on the same key — effectively free in the common case, a full extra read-plus-retry cycle in the rare case; this is a favorable trade against a pessimistic-locking design that would add overhead to every write, always, to guard against a rare event (§15 already explains why pessimistic locking wouldn't even work here, so this isn't really a trade being made — it's the only viable option that also happens to be cheap).
- `getCurrentKeysByType`'s pagination bounds memory/heap per page (§11, §13) — retire-detection over a `typeKey` with a very large Active population never materializes the full set in memory at once.
- Big Object writes (§9) are decoupled from the interactive write path entirely — a scheduled batch job, never inline with `commitVersion` — so archival volume/latency has zero effect on scan-time write performance.
- Platform Cache provider failures degrade to a cache miss, never an error (§17) — cache backend health can never make the durable read/write path slower or less available than it already is.

---

## 25. Extension Points

| Extension point | Where introduced | What it enables without touching `OI_GraphBuilder` or anything above it |
|---|---|---|
| `OI_IGraphStorageProvider` (pluggable durable/cache backends) | §3 (inherited from ADR-0012, elaborated here) | A new backend as a new provider class |
| Storage migration playbook (dual-write/verify/cutover/decommission) | §22 | A pre-agreed, low-risk procedure for ever actually exercising the pluggability above, on real subscriber data |
| Generic `VersionRecord` shape at the Repository boundary | §2, §4, §5 | A future third "flavor" of versioned graph record (if one is ever needed) without duplicating the five-operation contract a third time |
| `OI_IKeyValueCacheProvider` (separate, narrower interface from the durable provider contract) | §3, §10 | Swapping the L1 cache backend (e.g., a future Salesforce platform cache alternative) without touching `OI_IGraphStorageProvider` or its durable implementations at all |
| Optimistic-conflict retry hook | §15 | A future write path beyond the Graph Builder (none currently exists, none is planned) could reuse the same `OI_ConcurrencyException`-and-retry contract rather than inventing a second concurrency strategy |
| Promoted-attribute-slot schema growth (cross-ref GraphEngine.md §2/§20) | §21 | Confirms this layer's package-upgrade story already accommodates that extension point cleanly, without this document needing to redesign anything when it eventually ships |

---

## 26. Risks

| Risk | Why it could happen | Mitigation |
|---|---|---|
| **A future contributor re-splits `commitVersion` back into two callable steps** "for convenience" (e.g., a code path that only wants to insert without ever superseding anything, and exposes `insertOnly` as a public method that then gets reused incorrectly for the supersede case too) | The atomicity fix (§6) only holds as long as nothing outside `OI_GraphRepository` can invoke half of it | CodingStandards should treat any new public method on `OI_GraphRepository` that performs a DML insert against `OI_Graph_Node__c`/`OI_Graph_Edge__c` outside `commitVersion` itself as a review blocker — this is a process control, stated honestly as such (consistent with how GraphEngine.md §21 already flags the `Is_Current__c`-query-omission risk as a process control, not a runtime safeguard) |
| **Optimistic-retry storm under sustained, not just momentary, contention** on a hot key (e.g., a pathological case where many scanner types all legitimately touch the same node every run) | §15's retry is designed for a rare, narrow race; it is not a queueing/serialization mechanism, and repeated conflicts on the same key would retry repeatedly rather than queue | Capped at one retry (§15) before surfacing a task-level failure rather than retrying indefinitely; if this risk is ever observed in practice for a specific `typeKey`, the real fix is investigating why that type has genuine multi-writer contention (likely a Mutation Generator or Scanner-registry misconfiguration producing duplicate mutations for the same key), not tuning the retry count upward |
| **`getCurrentKeysByType` becomes a very expensive query for a `typeKey` with an extremely large Active population**, run repeatedly by every full scan's retire-detection pass | Retire-detection (§9, [MetadataScanner.md §15](MetadataScanner.md#15-mutation-generation-boundary)) runs on every full scan, not just occasionally | Pagination bounds memory (§13, §24), but total query cost across all pages still scales with population size; `Min_Rescan_Interval_Minutes__c` ([MetadataScanner.md §13](MetadataScanner.md#13-scan-scheduling)) already limits how often full scans (and therefore this query) run per type — no further mitigation is proposed here beyond what already exists, but it is named as a risk rather than assumed away, since this document is the first place the query's existence — and therefore its cost — is made explicit |
| **The Selector-delegation correction (§0, §12) is not actually enforced in review**, and a future `OI_GraphRepository` change reintroduces inline SOQL "just this once" | Naming convention alone (`*Selector` vs `*Repository`) doesn't prevent a class from containing a `[SELECT ...]` literal | CodingStandards §4's existing "no inline SOQL outside Selectors" rule already covers this generically; this document adds no new mechanism, only makes explicit that `OI_GraphRepository` is not exempt from a rule it could easily have been assumed exempt from, given how much else it's uniquely permitted to do (be the sole writer, run `without sharing`, etc.) |

---

## 27. Trade-offs

| Trade-off | Cost accepted | Benefit gained |
|---|---|---|
| Merging `insertVersion`+`flipCurrent` into one `commitVersion` call (§6) | Cannot bulk-commit multiple *different* keys' new versions in a single call the way a plain insert could (§11, §24) | Eliminates an entire class of partial-write corruption (zero-current / two-current rows) that a two-call design leaves structurally possible |
| Optimistic concurrency via External-ID collision, over pessimistic locking (§15) | A conflict costs a full extra read-and-retry round trip when it happens, and requires callers to handle a distinct exception type | Zero cost in the overwhelming common (no-contention) case, and is the only approach that actually works across separate Queueable transactions — pessimistic locking would have added constant overhead while providing no real protection (§15) |
| Selector delegation for all Custom-Object reads (§12) | One more class boundary to cross per read (Repository → Selector → SOQL) instead of the Repository querying inline | Keeps `CLAUDE.md`'s own Selector/Repository separation honestly applied to the platform's most complex Repository, rather than quietly exempt from a rule everything else follows |
| Generic `VersionRecord` shape instead of separate Node/Edge-specific Repository method families (§2) | The Repository contract carries two always-optional fields (`sourceKey`/`targetKey`) that only apply to one "flavor" of record | Halves the Repository's public method surface (one `getCurrentVersions`/`commitVersion`/etc. rather than a Node- and an Edge-flavored version of each), at no cost to the Graph Engine's own domain model, which keeps `OI_Node`/`OI_Edge` fully distinct one layer up (§23) |
| Archival decoupled from `commitVersion` (batch job, not inline) (§9) | Superseded rows sit in the live table for a bounded window before being swept — a small, accepted storage cost | Interactive-path write latency never depends on Big Object DML; archival failures can never threaten current-graph correctness |
| No self-healing for a violated `Is_Current__c` invariant (§7) | A genuinely corrupted state requires a human/code fix, not an automatic runtime repair | Corruption is surfaced loudly (logged, best-effort-but-not-silent) rather than compounding invisibly under an automatic "fix" that might itself be based on a wrong assumption about which row is actually correct |

---

## 28. Alternatives Considered

- **Version-commit atomicity** — (a) two separate calls, caller responsible for both succeeding (rejected — §0/§6, the defect this document exists to fix); (b) **chosen** — one atomic `commitVersion` call with internal savepoint/rollback; (c) a database-level trigger enforcing "at most one current row per key" as a backstop even if application code violates it — considered, rejected as redundant defense-in-depth for a guarantee a single well-tested Repository method should provide correctly the first time, and because a trigger enforcing this would need to run on every DML against these objects including the archival job's own reads/writes, adding complexity to a path (§9) already deliberately kept simple.
- **Concurrency strategy** — (a) pessimistic `FOR UPDATE` locking (rejected — §15, does not work across separate Queueable transactions); (b) a dedicated "lock" custom object row per key, acquired/released explicitly (rejected: reinvents a coordination mechanism the platform's own External-ID uniqueness constraint already provides for free, and adds an entire new object plus cleanup-on-crash problem — a stale lock row from a transaction that died mid-way would need its own timeout/reap logic); (c) **chosen** — optimistic concurrency via deterministic version-key collision detection, formalized in [ADR-0016](ADR/0016-repository-atomic-commit-and-optimistic-concurrency.md).
- **Selector vs. inline SOQL in the Repository** — (a) Repository writes its own SOQL inline, since it's "just for its own internal use" (rejected — §0/§12, this is the exact inconsistency this document corrects, and `CLAUDE.md` already answers this question generally); (b) **chosen** — full delegation to `OI_NodeSelector`/`OI_EdgeSelector`.
- **`VersionRecord` shape** — (a) fully separate `NodeVersionRecord`/`EdgeVersionRecord` types and method families (rejected for the Repository's own contract — §2/§23's duplication argument); (b) **chosen** — one generic shape with two optional edge-only fields; (c) a fully generic "attribute bag" with no named fields at all, not even `key`/`versionKey` (considered, rejected as over-generic — those fields are graph-mechanics infrastructure the Repository legitimately owns and reasons about directly, per GraphEngine.md §1's "generic about domain vocabulary, not about graph mechanics" distinction, which applies exactly the same way here).
- **Storage migration approach** — (a) never plan for it, redesign whenever/if it's actually needed (rejected: the entire justification for the Storage Provider abstraction is future migration flexibility — leaving the *procedure* undesigned would waste that investment when the day comes); (b) **chosen** — the dual-write/verify/cutover/decommission pattern (§22), documented now, built later.

---

## 29. Open Questions

1. **Exact archival threshold** (age vs. keep-last-N-versions vs. both) — inherited unresolved from [GraphEngine.md §24](GraphEngine.md#24-open-questions); this document's deeper treatment of the archival job (§9, §18) did not surface a reason to resolve it now, and it remains flagged for Roadmap Phase 5 rather than decided here just because this document goes deeper on the mechanism around it.
2. **Should the optimistic-retry cap (currently one retry, §15) be configurable via `OI_Settings__mdt` rather than a fixed constant?** Leaning toward "not yet" — no observed contention pattern currently justifies the added configuration surface, and `CLAUDE.md`'s "never invent missing business requirements" applies to configuration knobs as much as features. Revisit if the risk in §26 (retry storms) is ever actually observed.
3. **Does `getCurrentKeysByType` need a `graphScope` parameter now, ahead of any feature actually using multiple graph scopes?** Currently omitted — retire-detection today only ever operates within the single implicit default scope (GraphEngine.md §4), and adding an unused parameter "for future-proofing" is exactly the kind of speculative generality `CLAUDE.md`'s Core Principles warn against. If a future multi-scope feature (GraphEngine.md §20's drift-comparison extension point) needs scoped retire-detection, this method's signature can grow the parameter additively at that time.
4. **Is a Big Object read path for archived data (§3, "reserved for a future 'show history' feature") worth even stubbing now, or should `OI_BigObjectStorageProvider` ship in v1 with write-only capability and the read method added only when a history feature is actually scheduled?** Leaning toward write-only-for-now, consistent with question 3's reasoning, but not decided definitively here since it depends on Roadmap sequencing this document doesn't own.
5. **Should the dual-write storage-migration mode (§22) be designed generically enough to also cover a *within-backend* schema migration** (e.g., re-partitioning `Attributes_Json__c` content into promoted attribute slots, GraphEngine.md §2/§20's own extension point) **rather than only a cross-backend provider swap?** The two migrations look structurally similar (dual-write, verify via checksum, cutover) but this document scoped §22 to provider-level swaps only; whether the same playbook literally generalizes to a schema-shape migration within one provider is untested reasoning, not a confirmed design, and is flagged here rather than asserted.

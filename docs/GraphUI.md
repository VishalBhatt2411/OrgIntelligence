# Graph UI — Salesforce Org Intelligence Platform

Status: Draft v1
Owner: Architecture
Applies to: API v67.0

This document is the complete architectural specification of the Visual Graph UI — the primary user experience of the platform (`CLAUDE.md` §Design Philosophy: "the graph is the primary interface... Google Maps for Salesforce Metadata"). It covers component architecture, the Canvas, node/edge rendering, the Detail Panel, Search integration, Graph Engine integration, state management, expand/collapse, layout strategy, the tree-vs-graph decision, filtering, navigation aids, performance, accessibility, and package readiness. It contains no implementation code — only structure, contracts, and rationale.

**Visual authority:** [VisualDesignSpecification.md](VisualDesignSpecification.md) is the binding visual contract for Object Analyze mode and [ADR-0025](ADR/0025-reference-image-as-binding-visual-acceptance-contract.md) records that decision. This document governs component/data/interaction architecture. Where this document offers aesthetic discretion for Object Analyze mode, the approved reference removes that discretion.

**Governing constraints, stated once and enforced throughout, per this round's explicit mandate:**

- **The Canvas never fetches data.** `oiGraphCanvas` is a pure presentational component — props in, events out. Every Apex call in this subsystem is made by a container component, never by the Canvas or anything it renders.
- **The UI holds zero hardcoded Salesforce metadata-type branches.** Every type-aware rendering decision resolves through the Presentation Type Registry ([GraphEngine.md §17](GraphEngine.md#17-rendering-contract-for-lwc)) — a `typeKey` the registry has never seen renders with a generic default, never a crash and never a special case in component code.
- **Graph traversal is server-side, always.** Nothing in this document performs BFS/DFS in the browser; the client renders exactly what `OI_GraphTraversal` returns and asks for more via the same bounded contract.
- **The entire org graph is never loaded.** Every fetch is bounded by the existing hop-depth/node-count ceilings ([GraphEngine.md §12](GraphEngine.md#12-graph-traversal-algorithms)); this document adds a client-side working-set ceiling on top, for the same reason.
- **Collapse uses the reference-counting visibility model `GraphEngine.md` §11 already defines** — this document does not redesign that algorithm, it makes it precise at the client data-structure level (§13).
- **Search and graph traversal remain separate concerns** — a search result's `nodeKey` is a pointer the UI hands to the Graph Engine on a new, independent call ([SearchEngine.md §23](SearchEngine.md#23-graph-engine-integration)); nothing in this document blurs that boundary from the other side.

---

## 0. Relationship to Prior Documents — What This Resolves, Corrects, and Adds

Architecture §9 and [GraphEngine.md §17](GraphEngine.md#17-rendering-contract-for-lwc) already established real, correct constraints — the Canvas's generic contract, the Presentation Type Registry, virtualized rendering, top-down-data/bottom-up-events flow. Designing the actual UI at this depth surfaced one genuine ambiguity left unresolved in an already-Accepted document, and several places where "the UI exists" was assumed without anyone having decided its internal shape:

| Finding | Where it was (left) unresolved | Resolution |
|---|---|---|
| **The Presentation Type Registry's delivery mechanism was never decided.** [GraphEngine.md §17](GraphEngine.md#17-rendering-contract-for-lwc) describes it as "Custom Metadata **or** a versioned static resource, resolved at build time" — an open "or" in an Accepted document. A static-resource, build-time-baked registry would mean a new metadata type's styling requires a package push, directly contradicting the "new type = Custom Metadata record + Scanner class, zero code/deploy change" promise every other document in this set makes. | **Decided: Custom Metadata is the source of truth**, read once per session via a new `OI_SettingsController.getPresentationRegistry()` call (§8, §20/§21) and cached client-side — never baked into a static resource. Amendment to [GraphEngine.md §17](GraphEngine.md#17-rendering-contract-for-lwc), §0 Round 6 below. |
| **"Mini-map" was named as one capability but the existing API (`getMiniMapSummary` → coarse counts by `typeKey`, API.md §2.1) only ever supported one of two things people mean by that word.** | Nothing in Architecture §9 or API.md distinguished "a shrunk viewport thumbnail" (pure navigation aid, needs positions) from "a frontier-content preview" (needs aggregate counts, not positions) — the single `oiMiniMap` component name quietly conflated them. | §24 splits them explicitly: a client-only **Viewport Mini-map** (derived from already-rendered node positions, zero server cost) and a server-backed **Frontier Summary** (the existing `getMiniMapSummary` call) — both live inside `oiMiniMap`, serving different questions. |
| **GraphEngine.md §11's reference-counting algorithm is correct but stated at Apex-conceptual level** ("collapse decrements the supporting-count of each of the collapsed node's direct neighbors") — this is precise enough to review, not precise enough to build without a real, if small, design decision about *which* neighbors "direct" means. | Not a defect — the algorithm was never wrong, just not yet expressed as concrete client data structures. | §13 formalizes it exactly: a per-expand **revealed-set** `R(A)`, tracked separately from the running supporting-ancestor count, so collapse decrements precisely the neighbors *A's own expand* introduced — never a neighbor some other still-expanded ancestor is independently supporting. |
| **No document had chosen tree, graph, or hybrid visualization** — this round's explicit analysis requirement. | Genuinely new design work, not a correction. | §18 — hybrid, radial, graph-topology-with-tree-like-default-layout. Formalized in [ADR-0019](ADR/0019-hybrid-radial-graph-visualization.md). |
| **No document had chosen a rendering technology.** | Genuinely new design work. | §32 — SVG, virtualized, a small vendored layout-math library for force/radial positioning. Formalized in [ADR-0020](ADR/0020-svg-rendering-vendored-layout-library.md). |
| **Object Analyze mode's shared use of the generic radial canvas (§18) surfaces non-Object node types and has no directional (incoming/outgoing) framing** — confirmed, not hypothetical: an Object-centered 2-hop fetch genuinely returns ApexTrigger/Flow/PermissionSet/ApexClass nodes via `EXECUTES_ON`/`GRANTS_ACCESS_TO` edges, and ring-by-hop-distance layout has no notion of "references this" vs. "this references." | Not a defect in §18's choice for its intended, mode-agnostic scope — a narrower product question (Object analyze mode specifically) that scope was never meant to answer. | §42 — a second, narrowly-scoped directional lane layout for Object analyze mode only; §18's radial layout is unchanged and remains authoritative for Field mode, Record mode, and general exploration. Formalized in [ADR-0023](ADR/0023-object-relationship-lane-layout.md). |

Everything else in Architecture §9/§10 and GraphEngine.md §17 — the component list, LMS/`@api` communication split, top-down-data/bottom-up-events flow, the Canvas's generic input/output contract — holds and is elaborated, not contradicted, below.

**Validation worth stating plainly**: no new `OI_GraphController`/`OI_DependencyController` methods are required by anything in this document. The existing `getGraphFragment`/`getNodeDetail`/`getMiniMapSummary`/`getImpact` contracts (API.md §2.1, §2.3) already support every interaction this document designs, including per-node paginated re-expansion (§15) — a genuine confirmation that the Apex-side API surface was designed with the right shape, not a gap this document had to paper over.

---

## 1. Graph UI Philosophy

One sentence, borrowed directly from `CLAUDE.md` because nothing else needs saying first: **the graph is the primary interface; everything else in this document exists to make that interface trustworthy at the scale a real subscriber org actually has.**

Three words carry the rest, each inherited deliberately from a sibling document because the UI's philosophy is where the whole platform's design principles become visible to a human:

- **Generic** ([GraphEngine.md §1](GraphEngine.md#1-graph-philosophy)) — the UI renders `typeKey`s through a registry, never through code that knows what a Flow is.
- **Bounded** (same section) — nothing the UI does ever assumes it can ask for "everything." Every affordance in this document — expand, mini-map, filter — is a bounded, incremental request, never a full materialization.
- **Identity-only handoffs** ([SearchEngine.md §1](SearchEngine.md#1-search-philosophy)) — a search result, a breadcrumb entry, a mini-map badge: each is a pointer the UI resolves on demand, never a payload carried around speculatively.

**Prioritization, stated explicitly because this round's mandate asks for it directly**: clarity and discoverability over decoration. Every visual choice in §17–§21 is defended by "does this help a user understand what they're looking at and what to do next," never by "does this look impressive." A force-directed hairball with no readable structure is a worse product than a plainer layout a user can actually navigate — this document chooses the latter every time the two are in tension (§18).

---

## 2. User Journey

The mandated flow, elaborated with the decision point each arrow actually represents:

```
Search / Select Node
   ↓  (independent Apex call — SearchEngine.md, never inside this document's own fetch path)
Selected Node
   ↓  (getNodeDetail + a small, bounded initial getGraphFragment — §9)
Visual Graph (centered on the selected node)
   ↓  (user-initiated, per-node — never automatic)
Expand / Collapse
   ↓  (reference-counted — §13)
Explore relationships and dependencies
   ↓  (Detail Panel; optionally, explicit Impact Analysis — §7)
```

**Two decision points worth naming explicitly, because a naive implementation gets them wrong**: (1) selecting a node and expanding a node are different actions with different costs — selection fetches detail, never neighbors (§9); (2) viewing a node's dependencies (Impact Analysis, §7) is a *third*, distinct action from expand — it asks a different question ("what depends on this," a curated forward/reverse traversal) than expand does ("show me everything one hop away," an undirected-by-relevance-type neighborhood). Conflating any of these three into "clicking a node just does more stuff" is exactly how a UI ends up violating "never load the entire org" one reasonable-sounding feature request at a time.

---

## 3. Component Architecture

**The single most important structural rule in this document, stated once and enforced by every section after it**: every LWC in this subsystem is either a **container** (may call Apex) or **presentational** (never calls Apex, receives data via props, emits intent via events) — never both. This is the UI-layer parallel to the Selector/Repository/Service boundary rules that govern every other layer of this platform, and it is what makes "the Canvas must not directly fetch data" true structurally rather than by convention.

| Component | Kind | Calls Apex for |
|---|---|---|
| `oiGraphExplorer` | Container (the shell) | `getGraphFragment`, `getNodeDetail`, `getPresentationRegistry` (once, §8) — owns the current view |
| `oiSearchBar` | Container | `OI_SearchController.search`/`exactLookup` (SearchEngine.md §3) |
| `oiScanStatusPanel` | Container | `OI_ScanController.*` |
| `oiGraphCanvas` | **Presentational** | Nothing — renders `nodes`/`edges`/`frontier`/`viewport`, emits `expand`/`collapse`/`select`/`viewportChange` |
| `oiGraphNode` (new, §5) | Presentational | Nothing — one instance per rendered node |
| `oiNodeDetailPanel` | Container | `getNodeDetail` (already loaded by the shell in most flows, re-fetched on demand), `OI_DependencyController.getImpact` (§7, only on explicit user action) |
| `oiFilterPanel` | Presentational | Nothing — emits `filterChanged`, the shell decides whether that requires a new fetch (§22) |
| `oiBreadcrumbTrail` | Presentational | Nothing — emits `navigateTo(nodeKey)` |
| `oiMiniMap` | **Split, §24** | The Frontier Summary half calls `getMiniMapSummary`; the Viewport half is presentational |
| `oiObjectRelationshipCanvas` (new, §42) | Presentational | Nothing — Object analyze mode's canvas only; renders the lanes `objectRelationshipView.js` derives from already-fetched `nodes`/`edges`, emits `select`/`explorefromhere`/`edgeclick`. `oiGraphExplorer` renders this instead of `oiGraphCanvas` only when `analyzeMode === 'Object'` — Field/Record modes are unaffected |
| `oiRelationshipConnectorDetail` (new, §42) | Container | `OI_GraphController.getNavigationTarget`, via `c/metadataNavigation` — one connector's source/field/target detail |

**Data flow, restated precisely from Architecture §10**: `oiGraphExplorer` owns the authoritative view-state (§10, §11) and is the *only* place a fetch is triggered — every other component either renders a slice of that state (props down) or reports user intent (events up). No sibling ever reaches into another sibling's internals; cross-sibling coordination (e.g., Search selecting a node the Canvas must then center on) goes through the shell, exactly as Architecture §9's existing LMS/`@api` split already prescribes.

---

## 4. Graph Canvas Architecture

`oiGraphCanvas` is presentational (§3) and generic (§1) — its entire contract is the one [GraphEngine.md §17](GraphEngine.md#17-rendering-contract-for-lwc) already defines, elaborated here with the internal responsibilities that contract implies:

- **Renders** the current visible node/edge set (from view-state, §10/§11), applying layout (§17), the active filter (§22, client-side pass), and selection/hover visual state.
- **Virtualizes**: only nodes/edges within the current viewport plus a small margin get real SVG elements (§26, §32) — everything else in the working set exists in view-state but not in the DOM.
- **Never decides what "expand" or "collapse" *mean*** — it only emits the intent (`expand(nodeKey)`, `collapse(nodeKey)`) and lets the container resolve it against server data and view-state (§13). The Canvas has no knowledge of the reference-counting algorithm at all — that lives entirely in the container's view-state module (§10, §11), consistent with keeping the Canvas a pure rendering surface with nothing to unit-test beyond "given this data, does it render correctly" (§35).
- **Owns pan/zoom viewport math** (§16) as pure client-side state — panning and zooming never trigger a fetch (Architecture §9's existing rule, restated), only expand does.

---

## 5. Node Component Architecture

`oiGraphNode` — **new**, not previously named in Architecture §9's component list — one instance per currently-rendered (i.e., in-viewport, per virtualization, §4) node.

**Why a real LWC per node, unlike edges (§6)**: nodes need rich, individual interactivity — click-to-select, keyboard focus (§28), an expand/collapse affordance, hover detail preview, and type-specific icon/color resolution (§20) — genuinely per-instance state and behavior, not just a drawn shape. The bounded node-count ceiling ([GraphEngine.md §12](GraphEngine.md#12-graph-traversal-algorithms)) keeps the *maximum simultaneous instance count* small enough that LWC component overhead is a non-issue at this platform's own stated scale limits — the same ceiling that protects Apex heap also, as a side effect, protects Canvas component-instantiation cost.

**Contract**: `nodeKey`, `typeKey`, `label`, `secondaryKey`, `state` (props, from `NodeSummary`, [GraphEngine.md §4](GraphEngine.md#4-graph-model)); resolved `icon`/`color` (from the Presentation Type Registry, §20, looked up by the *container*, not by `oiGraphNode` itself — see below); `isSelected`, `isExpanded`, `hasFrontier` (view-state-derived); `supportingAncestorCount` (§13, exposed only for a debug/dev-mode overlay, never shown to end users — an internal-consistency aid, not a feature). Emits `select`, `expandToggle`.

**Why the registry lookup happens one level up, not inside `oiGraphNode` itself**: `oiGraphNode` receiving an already-resolved `icon`/`color` (rather than a `typeKey` it looks up itself) means the component has zero Custom-Metadata-shaped dependency of its own — it is trivially unit-testable with a plain prop fixture (§35), and the registry-fetch/cache lifecycle (§8, once per session) lives in exactly one place (the Canvas or the shell), never duplicated per node instance.

---

## 6. Edge Component Architecture

**Deliberately not a per-edge LWC instance** — this is a real, load-bearing performance decision, not an oversight matching §5's pattern for consistency's sake.

**Why**: a bounded node set can still imply a much larger edge set (a moderately connected metadata graph's edge count grows faster than its node count), and edges need far less individual interactivity than nodes — a label, a direction arrowhead, a hover-highlight, occasionally a click-for-detail. Instantiating a full LWC component per edge would multiply the platform's most numerous rendered element by real per-instance overhead for capability the interaction model doesn't need.

**Architecture, concretely**: edges are rendered directly by `oiGraphCanvas` as plain SVG `<path>` elements in a single render pass — one shape per visible edge, no child component boundary. Edge *styling* still goes through the Presentation Type Registry exactly as node styling does (§21) — genericity is preserved; only the componentization granularity differs. Interactivity (hover-highlight, click-to-select-edge for a label/detail tooltip) is handled by event delegation at the Canvas level (a single set of listeners covering all rendered paths), not per-edge listeners.

**Edge visibility has no independent reference count** (a clarification beyond what [GraphEngine.md §11](GraphEngine.md#11-expand-collapse-algorithm) states, since that section is scoped to nodes): **an edge is visible if and only if both of its endpoints are currently visible nodes** — a derived property, recomputed from the node visibility set, never tracked separately. This is simpler than mirroring §13's node algorithm for edges too, and is correct: an edge with a hidden endpoint has nothing meaningful to connect to on canvas, so there is no case where an edge should outlive either of its endpoints.

**Direction and multiplicity rendering** (elaborating [GraphEngine.md §3](GraphEngine.md#3-edge-model)'s "every edge is directed, always" and "symmetric relationships are two directed edges" decisions):
- Every rendered edge carries a single arrowhead at its target end — no undirected edges exist in this data model, so no undirected rendering mode exists in this UI either.
- **A→B and B→A of the *same* `typeKey` between the *same* node pair are merged into one bidirectional-styled edge (double arrowhead) for rendering purposes only** — the two edges remain distinct in the data/versioning/checksum sense (they are genuinely separate `OI_Graph_Edge__c` logical keys); only the Canvas's rendering pass detects the pair and draws one visual line instead of two overlapping ones. This is a rendering-layer optimization, not a data-model change, and is the direct, correct answer to §3's design decision rather than something that decision left unaddressed.
- Two *different*-`typeKey` edges between the same ordered pair are rendered as offset parallel curves, never overlapping straight lines — standard graph-visualization practice, necessary the moment a Flow both calls and is referenced by the same Apex class through two distinct relationship types.

---

## 7. Detail Panel

`oiNodeDetailPanel` is a container (§3): on selection, it calls `getNodeDetail(nodeKey)` — full attributes, lifecycle state, `lastSeenRunId` (API.md §2.1) — rendered generically via the registry (§20, a label-display template per `typeKey`, [GraphEngine.md §17](GraphEngine.md#17-rendering-contract-for-lwc)), never a hardcoded per-type field list.

**Impact Analysis is a distinct, explicit action inside this panel, never automatic on selection** — a deliberate interaction design decision, not an oversight: `getImpact` (API.md §2.3) is a heavier, depth-bounded traversal with its own cache ([Architecture §7](Architecture.md#7-dependency-engine-architecture)), and firing it on every selection would mean every click a user makes while browsing costs a dependency-analysis computation whether or not they wanted one — directly working against "never load more than needed." A "What depends on this?" / "What does this depend on?" affordance triggers `getImpact` only when chosen.

**Impact results integrate into the *same* reference-counting visibility model, not a second one** — this is a real design unification worth stating explicitly: when a user chooses "Highlight on Graph" for an impact result, the returned bounded subgraph's node/edge keys are merged into the Canvas's view-state exactly as if they had been revealed by expanding the origin node (§13) — they get `R(originNode)` membership and a supporting-ancestor count, so collapsing the origin node later correctly retracts them too. This avoids building a second, parallel visibility-tracking mechanism just for impact-analysis-sourced nodes, and it is a genuine, non-obvious design choice this document is making, not something any prior document already decided.

**Default rendering of impact results is the flat list** (table), consistent with `CLAUDE.md` §UI Philosophy's "tables are secondary but always-available" — "Highlight on Graph" is an *additional* action on top of the list, never a replacement for it, since not every user wants their canvas rearranged to answer a quick "how many things does this touch" question.

---

## 8. Search Integration

The entire integration surface is exactly what [SearchEngine.md §23](SearchEngine.md#23-graph-engine-integration) already specifies, from the UI's own side: a `SearchResultItem` with `resultKind = Metadata` carries a `nodeKey` (SearchEngine.md §4); selecting it is `oiGraphExplorer` issuing its own, independent `getGraphFragment`/`getNodeDetail` call — never something `oiSearchBar` or `OI_SearchService` does on the UI's behalf.

**Concretely, on selection from search**: the shell (1) calls `getNodeDetail(nodeKey)` to populate the Detail Panel, and (2) calls `getGraphFragment(nodeKey, hopDepth: 0)` — a bounded, zero-hop fetch that returns just the selected node itself (plus its `frontier` flag) as the new canvas center, **not** its neighbors. The user's next explicit expand action is what reveals anything beyond the selected node — this is the literal enforcement of "search and graph traversal remain separate concerns" from the UI side: even the transition *from* a search result *into* the graph view does not implicitly traverse.

**Record results** ([SearchEngine.md §12](SearchEngine.md#12-record-search)) carry no `nodeKey` by design — selecting one opens the standard Salesforce record page (outside this app's own canvas entirely) or, if `oiSearchBar` offers the optional Record-to-Object bridge ([SearchEngine.md §23](SearchEngine.md#23-graph-engine-integration)), triggers a *separate* `exactLookup` call the shell resolves before centering the canvas on the resulting Object node — never a direct record→canvas handoff, since a record is not, and never becomes, a graph node.

---

## 9. GraphEngine Integration

Restated as a contract table, since this is the seam every other section in this document ultimately reduces to:

| UI action | Apex call | Bounded by |
|---|---|---|
| Select a node (from search, breadcrumb, or canvas click) | `getNodeDetail(nodeKey)` + `getGraphFragment(nodeKey, hopDepth: 0)` | Single-node fetch, never a neighborhood |
| Expand a node | `getGraphFragment(nodeKey, hopDepth: 1, nodeTypeFilter[], edgeTypeFilter[], pageCursor, knownChecksums)` | `Max_Hop_Depth__c`/`Max_Traversal_Node_Count__c`, plus the fragment's own page size |
| Load more of one node's neighbors | Same call, `pageCursor` = that node's own stored cursor (§15) | Same ceiling, additive |
| Impact Analysis | `getImpact(nodeKey, direction, depth)` | `Architecture §7`'s configured depth default, its own cache |
| Frontier Summary (mini-map) | `getMiniMapSummary(nodeKey, radius)` | Coarse counts only — never full node/edge payloads |
| Presentation Type Registry | `getPresentationRegistry()` (new, §0, §20) | Fetched once per session, small, Custom-Metadata-backed |

**Nothing in this table is new API surface beyond `getPresentationRegistry`** (§0) — the validation already stated at the top of this document. `oiGraphExplorer` is the only component issuing any row of this table.

---

## 10. State Management

Elaborates Architecture §10's three-category model with the fourth, graph-specific concern that table didn't yet name:

| State category | Owner | New in this document |
|---|---|---|
| Ephemeral UI state | `oiGraphExplorer` via a view-state module (Architecture §10's `graphViewState.js`) | **Graph view-state** (§11) — the visible node/edge set, per-node supporting-ancestor sets and revealed-sets (§13), per-node pagination cursors (§15), viewport transform (§16) |
| Session state | `sessionStorage` | Unchanged — recent searches, last-viewed graph, breadcrumb trail |
| Server-authoritative state | Apex via imperative calls | Unchanged in mechanism; §9's table is its concrete instance for this subsystem |
| **Registry cache** (new) | `oiGraphExplorer`, fetched once via `getPresentationRegistry()` | Small, rarely-changing, held for the tab session — a fourth category worth naming because it is neither "ephemeral view state" (it doesn't change as the user browses) nor "server-authoritative graph state" (it's config, not graph data) |

No heavyweight state library is introduced (ADR-0008 stands unchanged) — the graph view-state module is a plain, reactive JS module exactly like the one Architecture §10 already specifies, just with more fields than that section enumerated before this document existed.

---

## 11. View-State Model

The concrete shape `graphViewState.js` holds, precisely enough to build against:

```
GraphViewState {
  centerNodeKey: string
  visibleNodes: Map<nodeKey, {
    summary: NodeSummary,
    supportingAncestors: Set<nodeKey>,   // §13
    revealedSet: Set<nodeKey>,            // §13 — populated only if this node has been expanded
    isExpanded: boolean,
    pageCursor: string | null,            // §15 — this node's own "load more neighbors" cursor
    hasMoreNeighbors: boolean
  }>
  visibleEdges: Map<edgeKey, EdgeSummary>  // derived visibility, §6 — no independent ref-count
  selectedNodeKey: string | null
  activeFilter: { typeFilter: Set<typeKey>, edgeTypeFilter: Set<typeKey> }  // §22
  viewport: { panX, panY, zoom }           // §16
  workingSetSize: number                   // §26/§27 — visibleNodes.size, checked before every expand
}
```

**One structural rule worth naming explicitly**: `centerNodeKey`'s entry in `visibleNodes` carries a permanent, synthetic supporting-ancestor (`"__root__"`) that is never removed by any collapse action — this is what makes the center node immune to being pruned by unrelated collapse operations elsewhere in the graph, and it is the concrete mechanism behind §2's "Visual Graph (centered on the selected node)" always remaining true regardless of what the user does next. Selecting a *new* node (a fresh search, a breadcrumb jump) replaces the entire `GraphViewState`, not just re-roots it in place — a new center means a new view, not an edit to the old one.

---

## 12. Expand/Collapse Behavior

- **Expand(nodeKey)**: if `visibleNodes[nodeKey]` has no `revealedSet` yet, this is a first expand — call `getGraphFragment(nodeKey, hopDepth: 1, ...)`. For each returned node X not already in `visibleNodes`: add it with `supportingAncestors = {nodeKey}`. For each returned X already visible: add `nodeKey` to its existing `supportingAncestors` (§13). Add every returned X's key to `visibleNodes[nodeKey].revealedSet`. Set `isExpanded = true`, store `nextCursor`/`hasMore` (§15).
- **Collapse(nodeKey)**: for each `X` in `visibleNodes[nodeKey].revealedSet`: remove `nodeKey` from `visibleNodes[X].supportingAncestors`; if that set is now empty, remove `X` from `visibleNodes` entirely (and, transitively per the derived-visibility rule §6, its now-dangling edges disappear too — but *not* recursively re-running collapse logic on `X`'s own `revealedSet`, since `X` was never itself expanded by this action, only revealed by it — see §13's precise statement of why this distinction matters). Set `visibleNodes[nodeKey].isExpanded = false`; **do not clear `revealedSet`** — a future re-expand reuses `knownChecksums` for everything still cached, even though it's no longer rendered (§14).
- **Re-expand after collapse**: calling Expand on an already-`revealedSet`-populated node re-issues the fetch (now benefiting from `knownChecksums` for anything the client still holds in the L3 cache, [GraphEngine.md §9](GraphEngine.md#9-incremental-graph-loading)) — this is not assumed to be free, but it is assumed to be cheap, since most of the payload will be checksum-matched skips rather than full re-serialization.

---

## 13. Reference-Counting Visibility Model

This section exists to make [GraphEngine.md §11](GraphEngine.md#11-expand-collapse-algorithm)'s algorithm precise enough to build without ambiguity — the algorithm is not changed, only made concrete, per §0's third finding.

**The subtlety, restated precisely**: "collapse decrements the supporting-count of each of the collapsed node's direct neighbors" is correct, but "direct neighbors" needs a precise referent, because a node A can have *incident edges* to nodes it did not itself reveal (a node B might be visible only because some other already-expanded node C revealed it, and A simply happens to have an edge to B too, discovered as part of A's own later expand — in which case A's expand call *does* add A to B's `supportingAncestors`, correctly, per §12's Expand rule; the question is only what happens on **collapse**).

**The precise rule, which is what §12 already encodes structurally**: collapsing A decrements support only for nodes in `revealedSet(A)` — the exact set A's own expand call introduced A's support for, tracked separately from the global `supportingAncestors` bookkeeping. This is *not* the same as "every node A currently has a visible edge to," and the difference matters: if A has an edge to B, but B was already visible before A was ever expanded (B is in some *other* node's `revealedSet`, not A's), then A's *own* expand call still added A to B's `supportingAncestors` (correctly reflecting "B is now also reachable via A") — collapsing A must remove exactly that contribution, which `revealedSet(A)` — populated at the moment of A's expand, containing every node A's expand response returned regardless of whether those nodes were new or already-visible — captures exactly and only.

**Why this one page didn't exist anywhere else**: [GraphEngine.md §11](GraphEngine.md#11-expand-collapse-algorithm) states the *outcome* correctly ("a node is only removed when its supporting-count reaches zero") but was written at the level of "the client view-state maintains... a count," without specifying the data structure precise enough to guarantee the count is decremented against the *right* set on collapse. This document supplies exactly that missing precision — a genuine elaboration, not a contradiction, and the reason §12's pseudocode reads the way it does.

**Verification obligation, carried into §35**: this is explicitly named, in both this document and GraphEngine.md §11, as "the one piece of logic that would be a subtle, hard-to-notice bug if implemented naively" — a dedicated test scenario (a diamond-shaped subgraph: two independently-expanded ancestors sharing one revealed descendant) is a required, not optional, test case.

---

## 14. Lazy Loading

Restates [GraphEngine.md §10](GraphEngine.md#10-lazy-loading-strategy)'s three dimensions from the UI's own vantage point, adding nothing new to the server-side rule, only the client-side behavior that honors it:

1. **Initial load**: nothing renders until a search selection or a direct `exactLookup` navigation provides a `centerNodeKey` (§8) — there is no default "landing" graph, consistent with GraphEngine's explicit rejection of a computed "most-connected nodes" seed view.
2. **Expand-triggered**: the *only* client action that calls `getGraphFragment` with `hopDepth > 0` is an explicit `expandToggle` event from `oiGraphNode` (§5) — pan, zoom, and hover never do, enforced structurally by the Canvas's contract (§4) simply not emitting a fetch-triggering event for any of those interactions.
3. **Attribute lazy load**: the Detail Panel's `getNodeDetail` call is the only path that ever requests full `attributes` — bulk `getGraphFragment` responses (and therefore every `oiGraphNode` instance) only ever see `NodeSummary`-shaped data, never attributes, matching GraphEngine's existing rule exactly.

---

## 15. Graph Pagination

Two independent pagination concerns, distinguished precisely because conflating them is a real risk (mirroring [SearchEngine.md §16](SearchEngine.md#16-pagination)'s equivalent caution for its own two pagination surfaces):

- **Per-node "load more neighbors"** (§11's `pageCursor` field, per entry in `visibleNodes`): when a hub node's expand response sets `hasMore = true`, `oiGraphNode`'s expandable affordance changes to an explicit "show more" state rather than reverting to collapsed — clicking it re-calls `getGraphFragment` with that node's own stored cursor, appending results to the *same* node's `revealedSet` (§12/§13) rather than starting a new one. Each node's cursor is independent; a user can be mid-pagination on two different hub nodes simultaneously without either cursor interfering with the other.
- **Working-set ceiling pagination is not really pagination at all** — it's a hard stop (§26), distinct from "there are more results the server would give you if asked" (the per-node case above). The UI must never conflate "hit the working-set ceiling" with "no more neighbors exist" — these render as different states (§26, §29).

---

## 16. Zoom and Pan

Pure client-side viewport transform (`{panX, panY, zoom}`, §11) — no server interaction of any kind, matching Architecture §9's existing "progressive interaction contract" rule exactly. Constraints worth stating because they affect §26/§32: zoom has a practical floor (below which individual nodes become illegible and interaction targets shrink below a usable/accessible tap-target size, §28, §31) and a practical ceiling (beyond which virtualization's viewport-margin calculation, §4/§26, would need to track a proportionally larger candidate set) — both are UI-tuning constants, not architectural decisions, and are not specified numerically in this document.

---

## 17. Layout Strategy

**Radial/egocentric layout, centered on the current `centerNodeKey`, ring position determined by hop-distance from center** — chosen over both a literal tree layout and an undirected force-directed layout, for reasons developed fully in §18. **Scope note**: this is the layout for Field mode, Record mode, and general multi-type graph exploration. Object analyze mode uses a second, narrower, directional lane layout instead — see §42 and [ADR-0023](ADR/0023-object-relationship-lane-layout.md) — because it asks a different, single-type-directional question this radial strategy was never designed to answer.

- **Ring assignment**: a node's ring = its shortest currently-known hop-distance from `centerNodeKey` within the visible set (not a globally-computed shortest path against the full graph — the visible set is all the client has, and that is sufficient for a *layout* decision, as opposed to a *correctness* decision like traversal, which stays entirely server-side per this round's mandate).
- **Within-ring positioning**: a light force-relaxation pass (repulsion between same-ring nodes, weak attraction toward the parent that revealed them) to reduce edge crossings and even out angular spacing — this is where the vendored layout-math library (§32) does its work; it never decides *which* nodes exist or *what* the graph's true topology is, only *where* to draw already-known nodes.
- **Re-layout triggers**: expand (new nodes need ring/angle assignment), collapse (freed-up angular space can be redistributed, though this document does not mandate an animated re-flow — a static re-layout is an acceptable, simpler v1 choice), and filter changes (§22, hidden nodes are skipped in the layout pass entirely, not just visually dimmed, so remaining nodes can use the freed space).
- **The center node never moves** — it is anchored at the visual origin for the entire duration of one `GraphViewState` (§11); this is what keeps a user's spatial mental model stable across many expand/collapse actions, a direct, concrete expression of §1's "clarity over decoration" priority.

---

## 18. Tree vs. Graph Visualization Strategy

The explicit analysis this round requires. Three options, weighed honestly against this platform's own, already-established data model — not against visualization aesthetics in the abstract. **Scope note, added by [ADR-0023](ADR/0023-object-relationship-lane-layout.md)**: the choice below governs the default, mode-agnostic canvas (Field mode, Record mode, general exploration). Object analyze mode's own, narrower question — object-to-object structure only, not a multi-type neighborhood — is answered by a second, purpose-built layout, §42, that coexists with rather than revisits this decision.

**Option A — hierarchical tree.** Rejected as the *sole* strategy, decisively, on data-model grounds established well before this document: [ADR-0001](ADR/0001-graph-data-model-as-core-abstraction.md) explicitly rejected a one-parent-per-relationship model because "relationships are inherently cross-type... an edge can connect any two node types"; [GraphEngine.md §11](GraphEngine.md#11-expand-collapse-algorithm) explicitly designs for "a node reachable through more than one expanded ancestor... common in metadata graphs, e.g. a field referenced by two different Flows"; [Architecture.md §7](Architecture.md#7-dependency-engine-architecture) explicitly requires cycle detection because "Apex `DEPENDS_ON`/`CALLS` graphs can be cyclic." A literal tree data structure cannot represent a node with two parents without either duplicating it (violating this round's explicit "shared nodes must not be duplicated unnecessarily" rule) or arbitrarily picking one parent and silently hiding the other relationship (a correctness failure, not just an aesthetic one — a user would draw wrong conclusions about what depends on what). **A tree is the wrong data structure for this product's actual data**, not merely a suboptimal visualization choice.

**Option B — undirected, free-form directed graph (force-directed, no imposed hierarchy).** Considered seriously — this is topologically correct (handles cycles and shared nodes natively) and is the "traditional" answer for arbitrary graph visualization. Rejected as the *default* presentation, though not because it's wrong, but because it's a poor fit for *this product's specific interaction model*: the mandated user journey (§2) is explicitly egocentric — "a user selects **a** node and receives a visual graph" — there is always a meaningful center, and a pure force-directed layout treats every node symmetrically, actively working against the "center node never moves, spatial mental model stays stable" property §17 identifies as central to clarity. A pure force layout also degrades badly exactly at the failure mode this round explicitly worries about — "many nodes connected to one node" (§26) — producing an unreadable starburst with no help from the layout algorithm itself.

**Option C — hybrid: graph topology, tree-like radial layout. Chosen.** The underlying data structure and every traversal/visibility algorithm (§12, §13) is a true directed graph — cycles, shared nodes, and multiple "parents" are all first-class, exactly matching how the Graph Engine itself models data (GraphEngine.md §1, §3). The *visual arrangement* defaults to a radial layout that *looks* tree-like for the common case (most metadata relationships genuinely do have a natural "outward from here" direction — an Object's Fields, a Flow's called classes) — giving the readability benefit of a tree without the data-structure lie. When a node is genuinely shared (multiple supporting ancestors, §13), it renders once, in whichever ring its shortest current hop-distance places it, with visible incoming edges from every currently-expanded ancestor that supports it — the UI's honest visual answer to "this thing has more than one parent," rather than a hidden or duplicated one.

**This choice directly validates, rather than merely follows, `CLAUDE.md`'s own stated design inspiration**: "Neo4j Browser" is named explicitly in `CLAUDE.md` §Design Philosophy, and Neo4j Browser's own default visualization is exactly this pattern — an egocentric, radially-arranged, topologically-honest graph, not a literal tree and not an undirected force-directed hairball. Choosing Option C is this document independently arriving at the same answer the product's own stated inspiration already uses, which is worth noting as convergent validation rather than coincidence. Full formalization: [ADR-0019](ADR/0019-hybrid-radial-graph-visualization.md).

---

## 19. Directional Dependency Visualization

- **Every edge shows direction** (§6) — an arrowhead at the target end, never an ambiguous undirected line, matching the data model's own "every edge is directed, always" rule exactly.
- **Forward vs. reverse dependency framing in the Detail Panel** ([Architecture §7](Architecture.md#7-dependency-engine-architecture)): "What does this depend on" (forward — outbound `DEPENDS_ON`/`CALLS`/`REFERENCES`/`INVOKES`/`USES_API` edges) and "What depends on this" (reverse — the same edge types, inbound) are presented as two distinct, explicitly-labeled actions, never a single "show dependencies" button that silently picks a direction — the direction *is* the question being asked, and hiding that choice from the user would hide the single most useful distinction Impact Analysis offers.
- **Edge-type semantics are never hardcoded in the UI** — which edge `typeKey`s count as "dependency-flavored" for the forward/reverse Impact Analysis framing is a Dependency Engine Service concern (Architecture §7's existing list), not a UI concern; the UI only ever renders whatever `OI_ImpactResultDTO` returns, generically, through the same registry-driven rendering (§21) as ordinary expand-revealed edges.

---

## 20. Node-Type Rendering Registry

Consumes the Domain Type Registry (`OI_Node_Type_Descriptor__mdt`, DataModel §4.1) via the new `getPresentationRegistry()` call (§0), resolved once per session and cached client-side (§10) — the concrete, decided answer to GraphEngine.md §17's previously-open "Custom Metadata or a static resource" question.

**Lookup contract**: `typeKey → { iconName, colorToken, labelDisplayTemplate }`. **Unregistered `typeKey` behavior, stated explicitly because "the UI must render unknown future node types through the registry" is a hard mandate, not a nicety**: a `typeKey` absent from the fetched registry resolves to a fixed, generic default (`standard:custom` icon, a neutral color token, the raw `label` field with no template) — never an error, never a blank/broken node render, never a client-side crash. This is directly, deliberately testable (§35): a fixture with a synthetic, never-registered `typeKey` must render successfully with the generic default, and this test is what actually proves the "future metadata types render automatically" claim rather than merely asserting it in prose.

**Where the lookup happens**: at the container level (`oiGraphExplorer`/`oiGraphCanvas`), resolving `typeKey → {icon, color}` *before* handing already-resolved visual props down to `oiGraphNode` (§5) — `oiGraphNode` itself never touches the registry, keeping it a simpler, more directly testable component.

**§20.1 Per-object icon override (Object analyze mode only) — added, not a contradiction.** The registry above is deliberately generic per metadata *category* (`typeKey`) — every `SalesforceMetadata.CustomObject` node shares one `typeKey` regardless of whether the underlying SObject is Account, Contact, or a subscriber's own custom object — so a design mandate for Object analyze mode's neighbor cards to show each object's own real, Setup-assigned icon (Contact's person icon, Opportunity's own icon, a customer's custom object's own assigned icon) is a genuinely different lookup axis (per-object-API-name, not per-`typeKey`) that §20's registry was never designed to answer and should not be overloaded to answer.

Resolved via `lightning/uiObjectInfoApi`'s `getObjectInfos` wire adapter (CLAUDE.md's API Selection Priority ranks UI API above Tooling/REST/SOQL for exactly this shape of read) — `oiGraphExplorer.js` reactively wires the distinct Object-node API names currently in the working set, parses each result's `themeInfo.iconUrl` (e.g. `.../standard/account_120.png` → `standard:account`, `.../custom/custom18_120.png` → `custom:custom18`) back into a `<lightning-icon>` name, and overrides `allCanvasNodes`' registry-resolved icon for `SalesforceMetadata.CustomObject` nodes only, before handing props down to `oiRelationshipCanvas`/`oiGraphNode` — the lookup still happens one level up from the presentational layer, consistent with §20's own placement rule. No new Apex surface, no Custom Metadata to maintain per object: Lightning Data Service already knows every org's assigned standard/custom icon (falling back to whatever generic icon that object's own admin assigned, or none) and enforces the same FLS/CRUD a user already has. Unregistered/unresolvable cases (UI API has no `themeInfo` for that object, or the wire hasn't resolved yet) fall back to §20's existing generic registry icon — never an error, matching this section's own unregistered-type contract. Field mode and Record mode's neighbor rendering are unaffected — this override applies only where `oiGraphExplorer` resolves `allCanvasNodes` for Object-typed nodes.

---

## 21. Edge-Type Rendering Registry

Identical mechanism and identical unregistered-type fallback behavior as §20, consuming `OI_Edge_Type_Descriptor__mdt` (`typeKey → { displayLabel, lineStyle }`, DataModel §4.1) via the same `getPresentationRegistry()` call — one fetch, both registries, since they are read together at the same lifecycle moment and there is no benefit to two round-trips for two small, related config sets.

**`lineStyle` resolves to**: stroke pattern (solid/dashed/dotted — e.g., a `REFERENCES` edge rendered differently from a `MASTER_DETAIL_TO` edge) and, combined with §6's direction/multiplicity rendering rules, the complete visual specification for one edge — nothing about *which* edges exist or *what* they mean is ever decided by this registry; it only ever answers "how should an edge of this already-known type look."

---

## 22. Filtering

Two layers, deliberately, answering two different questions:

1. **Client-side visual filter** (immediate, zero round-trip): `oiFilterPanel` emits `filterChanged({typeFilter, edgeTypeFilter})`; the shell updates `GraphViewState.activeFilter` (§11) and the Canvas's next render pass excludes non-matching already-loaded nodes/edges from both rendering *and* the layout algorithm (§17) — freed space is reclaimed, not just visually blanked.
2. **Server-side fetch filter** (on the *next* expand): the same `typeFilter`/`edgeTypeFilter` values are passed as `nodeTypeFilter[]`/`edgeTypeFilter[]` on every subsequent `getGraphFragment` call (§9's table) — so a filter set *before* expanding a hub node means the server never returns, and the client never has to hide, types the user has already said they don't want to see. This is the direct answer to "why not just client-side": without this, every future expand would over-fetch data the filter immediately discards, wasting exactly the round-trip/payload budget [GraphEngine.md §15](GraphEngine.md#15-performance-considerations) is designed to protect.

Clearing the filter never re-fetches automatically — previously-filtered-out-but-already-fetched nodes simply reappear (they were never actually discarded from view-state, only hidden from render/layout); *new* data matching the now-broader filter requires a fresh expand, exactly like any other lazy-load boundary (§14).

---

## 23. Breadcrumbs

`oiBreadcrumbTrail` is presentational (§3): each entry is a `{nodeKey, label}` pair pushed onto a client-only stack whenever the *center* changes (a new search selection, a breadcrumb-navigate-back, or — the one graph-native trigger — the user explicitly "re-centers" the view on a currently-expanded node, a small additional affordance this document introduces so a user exploring several hops out from the original center can make a newly-interesting node the new anchor without losing the path that led there). Clicking a breadcrumb entry emits `navigateTo(nodeKey)`, which the shell resolves exactly like a fresh search selection (§8) — a full `GraphViewState` replacement, not a partial rewind, since the visible working set at the time of re-centering may no longer be entirely relevant to the new center.

**Not tracked in breadcrumbs**: individual expand/collapse actions within one center's exploration — the trail is about *centers visited*, not *every interaction taken*, matching how a physical breadcrumb trail in a UI convention generally works (major navigation points, not every micro-action) and keeping the trail short and genuinely useful rather than a noisy full action log.

---

## 24. Mini-Map

Split explicitly into two, per §0's finding — one component, two internally distinct halves:

- **Viewport Mini-map** (client-only, presentational): a small, always-cheap thumbnail derived from the already-rendered node positions (§17) and the current pan/zoom transform (§16) — pure geometry, zero server cost, answers "where am I, relative to everything I've already loaded." Updates on every pan/zoom/expand/collapse, since all of its inputs are already-local state.
- **Frontier Summary** (container, server-backed): calls `getMiniMapSummary(nodeKey, radius)` for the *currently selected* node — coarse counts by `typeKey` within a radius the user hasn't fetched yet — rendered as small count badges ("12 more Fields," "3 more Flows") rather than any attempt at a spatial preview, since the backing data has no positions to show. Answers a genuinely different question: "is expanding further worth it, and in which direction (which type)."

**Why both, not one**: collapsing them into a single always-server-backed widget would make the cheap, purely-local navigation aid (viewport thumbnail) needlessly pay a round-trip cost it never actually needs; collapsing them into a single always-client-only widget would lose the genuinely useful "preview the frontier before committing to an expand" capability the existing `getMiniMapSummary` API was already built to provide. Keeping them as two halves of one component is the honest reflection of what the underlying data actually supports.

---

## 25. Performance Strategy

Consolidated, each item traceable to a section above:

- Virtualized rendering (§4, §26) — only in-viewport-plus-margin nodes/edges get real SVG elements, regardless of working-set size.
- Edges are never componentized (§6) — a single Canvas-owned render pass, not N child-component instantiations.
- Registry lookups happen once per session, at the container level, never per node/edge instance (§20/§21).
- Filter state is passed server-side on every subsequent fetch (§22), preventing repeated over-fetch-then-discard cycles.
- Per-node pagination cursors (§15) mean a hub node's "load more" never re-fetches already-seen neighbors.
- `knownChecksums` (inherited from [GraphEngine.md §9](GraphEngine.md#9-incremental-graph-loading)) is populated from the client's currently-held checksums on every expand/re-expand call, minimizing re-serialization cost exactly as that section already designs for.
- The center node's position is fixed for the lifetime of one view (§17) — re-layout passes never need to recompute a global anchor, only relative positions.

---

## 26. Large Graph Handling

The two named failure modes this round calls out explicitly, addressed directly:

**"The graph must remain usable when many nodes are connected to one node" (hub nodes)**: server-side pagination already bounds any single expand response (§15); this document adds a client-side rendering strategy on top, because 50 simultaneously-revealed raw neighbors is still visually unusable even when it's a bounded, correctly-paginated 50. **Neighbors revealed by one expand are grouped by `typeKey` in the layout pass** (§17) — same-type neighbors cluster angularly rather than scattering independently — with a "show N more of this type" progressive-disclosure affordance *within* an already-fetched page (client-side only, zero extra round-trip) if a single type's count within one page is itself large enough to be visually noisy. This is a direct, concrete answer to the named requirement, not just a restatement of the server-side ceiling that already existed.

**Cumulative working-set ceiling** (distinct from any single request's ceiling): `GraphViewState.workingSetSize` (§11) is checked before every expand against `OI_Settings__mdt.Max_Canvas_Working_Set__c` (new, §0/DataModel change). Hitting it does **not** silently refuse the expand or silently evict currently-visible nodes the user is actively looking at — it surfaces an explicit state (§29): "Your graph has gotten large — collapse a branch you're done exploring to continue," the same "no silent caps" honesty principle [SearchEngine.md §4](SearchEngine.md#4-search-response-model)'s `truncated` flag already established for this platform's search results, applied here to graph exploration.

---

## 27. Browser Memory Management

Elaborates [GraphEngine.md §16](GraphEngine.md#16-memory-management)'s client-side half with the concrete mechanism that section named but didn't fully specify:

- **Rendered DOM/SVG elements**: bounded by virtualization (§4, §26) regardless of working-set size — a 500-node working set with 40 currently in viewport costs roughly 40 nodes' worth of real elements, not 500.
- **View-state memory** (the full `GraphViewState`, §11): bounded by `Max_Canvas_Working_Set__c` (§26) directly — this is the actual ceiling on JS heap growth during a long browsing session, since view-state (unlike rendered DOM) exists for every node in the working set regardless of viewport visibility.
- **L3 cache** ([GraphEngine.md §14](GraphEngine.md#14-graph-caching-strategy), `Client_Cache_LRU_Size__c`): a *separate* bound from the working set — L3 can and typically does hold more than what's currently in the working set (previously-collapsed-and-evicted-from-working-set nodes' checksums remain cached for a cheap re-expand, §12), and eviction from L3 never implies eviction from the working set or vice versa; the two caches serve different purposes and are not the same data structure.
- **Passive housekeeping**: when the working-set ceiling is approached (not yet hit), the least-recently-interacted-with collapsed subtree(s) — nodes with no current `isExpanded = true` in their own right and the smallest/staleset supporting-ancestor footprint — are proactively evicted from the working set (not merely visually hidden) *before* the hard ceiling forces an explicit user-facing stop (§26), giving most long sessions a chance to never actually hit the "please collapse something" state at all.

---

## 28. Accessibility

Per `CLAUDE.md` §UI Philosophy's explicit "keyboard navigation" and "dark mode" commitments, and CodingStandards §10's existing ARIA/keyboard-equivalent rule, made concrete for a graph canvas specifically (a genuinely harder accessibility surface than a form or a list, worth real design attention rather than a one-line assertion):

- **SVG rendering (§32) is chosen partly *for* this reason**: real DOM elements per visible node (§5) mean each is natively focusable, tab-orderable, and ARIA-labelable — a Canvas/WebGL bitmap rendering would require reimplementing all of this via a synthetic accessibility tree, real but substantially more work for the same outcome.
- **Keyboard model**: arrow keys move focus between currently-visible, currently-connected nodes (graph-aware focus traversal, not raster tab-order); `Enter`/`Space` on a focused node triggers select; a dedicated key (e.g., `+`/`-`) triggers expand/collapse on the focused node — every mouse-driven interaction in this document has a named keyboard equivalent, satisfying CodingStandards §10's existing rule rather than treating the graph canvas as an exception to it.
- **Screen reader semantics**: each `oiGraphNode` carries an ARIA label composed from the registry's `labelDisplayTemplate` (§20) plus its type's display label and current expand state ("Account, Custom Object, collapsed, 12 more relationships available") — generic, registry-driven, never a hardcoded per-type string, consistent with this document's genericity rule extending fully into assistive-technology-facing text, not just visual styling.
- **Color is never the sole signal**: type distinction relies on icon + label first, color token second (§20) — a colorblind user relying on icon/text alone loses no functional information, only a secondary visual cue.
- **Dark mode**: the Presentation Type Registry's `colorToken`s (§20/§21) are design tokens, not literal hex values — resolving them through SLDS's existing dark-mode-aware token system (CodingStandards §10) means dark mode support falls out of the registry design already existing for genericity reasons, not a separate effort.

---

## 29. Error / Loading / Empty States

Three distinct states per major async boundary (§9's table), each with an honest, specific UI response — never a single generic spinner/blank-screen/toast covering all three:

| Boundary | Loading | Empty | Error |
|---|---|---|---|
| Initial node selection | Skeleton Detail Panel + center-node placeholder on Canvas | N/A (a selected node always exists by definition) | Sanitized message + correlation ID (Architecture §12); "try again" retries the same call |
| Expand | The expanding node shows an in-progress affordance (not a full-canvas spinner — only that node's neighborhood is pending) | **"No further relationships of this type"** — a real, valid outcome, rendered as a quiet, permanent state on that node (frontier badge cleared), never confused with an error | Same sanitized-message pattern; the node reverts to its pre-expand collapsed state so a retry is a clean re-attempt, not a repair of partial state |
| Working-set ceiling hit | N/A | N/A | Not an error — the explicit, named state from §26, visually distinct from a failure (an informational banner, not a red error toast) |
| Frontier Summary | Small inline loading indicator on the mini-map widget only, never blocking the main Canvas | Zero counts render as "fully explored from here" | Frontier Summary failure degrades to simply not showing counts — never blocks or errors the rest of the UI, since it is a secondary aid, not a critical path |
| Scan-in-progress (viewing a graph while a scan runs) | `oiScanStatusPanel`'s existing live progress (Architecture §6/§9), surfaced as a persistent but non-blocking banner | N/A | N/A — this is Metadata Scanner subsystem territory, referenced here only for completeness |

**Empty-state honesty, worth one more explicit sentence**: "no further relationships" and "you've hit the working-set ceiling" and "this request failed" are three states a naive implementation could easily render identically (a blank area, a generic message) — this document treats conflating any two of them as a defect, not a stylistic nitpick, because a user's correct next action differs completely between them (do nothing further / collapse something / retry).

---

## 30. Security

Nothing new is introduced at this layer — every Apex call this document's components make (§9's table) is already gated exactly as Architecture §14/API.md already specify (`OI_View_Graph` for graph reads, the relevant permission for Impact Analysis, Search's own domain-specific gating per [SearchEngine.md §18](SearchEngine.md#18-security-and-sharing)). Two points specific to this document, worth stating explicitly:

- **The Presentation Type Registry carries no sensitive data** — icon names, color tokens, display templates — and `getPresentationRegistry()` requires no permission beyond baseline authenticated access; it is configuration about *how to draw things*, not data about the org, and gating it behind `OI_View_Graph` would be over-cautious for zero actual protection benefit (a decision worth stating rather than leaving implicit, since a reviewer might otherwise reasonably ask why this one method looks under-gated compared to every other Controller method in this platform).
- **The Canvas being presentational-only (§3) is itself a security property, not just an architectural one**: since `oiGraphCanvas` and `oiGraphNode` never call Apex, there is no code path in this subsystem where a permission check could be *forgotten* at the Canvas layer — every check that matters lives at the container boundary, in exactly the places Architecture §14 already requires them, with nothing downstream of that boundary able to bypass it by construction.

---

## 31. Mobile/Responsive Considerations

**Honest scoping, stated directly rather than implied**: full interactive graph exploration — multi-hop expand/collapse, precise pan/zoom, keyboard-equivalent-rich interaction (§28) — is a desktop/tablet-first experience. This is not a gap this document apologizes for; it is the correct scope for the actual user (a Salesforce administrator or architect performing deliberate technical investigation, `CLAUDE.md`'s stated audience), not a casual mobile-browsing use case.

- **Tablet**: touch pan/pinch-zoom map directly onto the same viewport transform (§16) mouse-driven pan/zoom already uses — no separate interaction model needed, since both ultimately just update `{panX, panY, zoom}`.
- **Phone-width viewports**: below a defined breakpoint, the Canvas is **not** force-fit onto the available space — the shell instead defaults to the flat-list/table secondary rendering of the current node's neighborhood (already a first-class, always-available view per `CLAUDE.md` §UI Philosophy and §7's own Impact Analysis default) rather than attempting a graph canvas experience that would be unusable at that size regardless of engineering effort spent on it. This is the same honest-limitation posture [SearchEngine.md §9](SearchEngine.md#9-partial--fuzzy-search) takes for fuzzy search — naming a real scope boundary rather than pretending full parity everywhere is both achievable and worth building.

---

## 32. Canvas Technology/Library Decision

**Chosen: SVG rendering, virtualized, with a small vendored library supplying force/radial layout math only — never Canvas 2D, never WebGL, in v1.**

**Requirements driving the decision**: bounded rendered-element counts (this platform explicitly never loads unbounded data, §26, so raw rendering throughput at massive scale is not a real constraint the way it would be for, say, a genuine big-data visualization tool); rich per-node interactivity and accessibility (§5, §28); no CDN-loaded scripts, CSP compliance, pinned-version/licensed static resources (`CLAUDE.md` §Technical Stack, CodingStandards §11); "lightest solution capable of solving the problem" (`CLAUDE.md` §API Selection Priority's underlying principle, applied here to a UI-technology choice rather than an API choice).

- **SVG over Canvas 2D/WebGL**: real DOM elements per node give accessibility (§28), hit-testing, and CSS/SLDS-token styling integration for free — capabilities a bitmap rendering surface would have to reimplement by hand. At this platform's own explicitly bounded scale (never an unbounded graph, node-count ceilings enforced server-side regardless of UI technology), SVG's per-element overhead is a non-issue; adopting Canvas/WebGL's added complexity to solve a scale problem this platform has already structurally refused to have would be solving a problem that doesn't exist here, at the cost of real accessibility and simplicity.
- **A vendored layout-math library, not a full graph-visualization framework**: this document deliberately scopes the vendored dependency narrowly — force/radial layout position calculation only (§17), a well-understood, self-contained piece of math (the kind a library like a force-simulation module provides) — rather than adopting an entire opinionated graph-rendering framework that would also want to own rendering, data-binding, and interaction, all of which this document has already designed independently and specifically for this platform's own constraints (registry-driven rendering, reference-counted visibility, container/presentational split). A narrow dependency is easier to audit for CSP/license compliance (CodingStandards §11), easier to replace if it ever becomes a liability, and doesn't fight this document's own architecture for control of concerns it doesn't need to own.
- **Package readiness**: whichever specific library is selected at implementation time is vendored as a Static Resource, pinned to an exact version, checked in with its license, and reviewed for CSP compliance before use — the existing CodingStandards §11 rule, restated here because this is the component that rule was written for.

Full rationale and rejected alternatives: [ADR-0020](ADR/0020-svg-rendering-vendored-layout-library.md).

---

## 33. LWC Architecture

Consolidates the component list (§3) with the folder/naming convention Architecture §3/CodingStandards §1 already establish — no new convention invented, only the concrete file list this document's design implies:

```
lwc/
├── oiGraphExplorer/        # container — the shell, owns GraphViewState
├── oiGraphCanvas/          # presentational — renders/lays out the visible set (Field/Record modes, general exploration)
├── oiGraphNode/            # presentational — new (§5), one per rendered node
├── oiObjectRelationshipCanvas/  # presentational — new (§42), Object analyze mode only
├── oiRelationshipConnectorDetail/  # container — new (§42), one connector's source/field/target detail
├── oiNodeDetailPanel/      # container — getNodeDetail, getImpact
├── oiSearchBar/            # container — unchanged, SearchEngine.md
├── oiFilterPanel/          # presentational — unchanged (Field/Record modes only, §42)
├── oiBreadcrumbTrail/      # presentational — unchanged
├── oiMiniMap/               # split (§24) — container half + presentational half
├── oiScanStatusPanel/      # container — unchanged
├── oiSettingsPanel/        # container — unchanged
├── oiAdminConsole/         # container — unchanged
└── oiSharedUtils/
    ├── graphViewState.js    # the module implementing §11/§12/§13
    ├── presentationRegistry.js  # the module implementing §20/§21's fetch-once-cache pattern
    └── objectRelationshipView.js  # new (§42) — pure transform: nodes/edges/centerNodeKey -> lanes, Object mode only
```

No component in this list violates the container/presentational split (§3) — this is the concrete artifact a code reviewer checks against, the same way the Apex naming table (Architecture §3) lets a reviewer tell a class's layer from its name alone.

---

## 34. Apex ↔ LWC Contract

Restates §9's table as the authoritative DTO-level contract, plus the one new method:

| Method | Owner (existing/new) | Contract |
|---|---|---|
| `getGraphFragment` | `OI_GraphController` (existing) | Unchanged — [GraphEngine.md §18](GraphEngine.md#18-api-contracts-between-apex-and-lwc) |
| `getNodeDetail` | `OI_GraphController` (existing) | Unchanged |
| `getMiniMapSummary` | `OI_GraphController` (existing) | Unchanged |
| `getImpact` | `OI_DependencyController` (existing) | Unchanged |
| `getPresentationRegistry` | `OI_SettingsController` (**new**, §0) | Input: none. Output: `List<OI_NodeTypeDescriptorDTO>` (`typeKey`, `displayLabel`, `iconName`, `colorToken`), `List<OI_EdgeTypeDescriptorDTO>` (`typeKey`, `displayLabel`, `lineStyle`) — read-only, cacheable (`@AuraEnabled(cacheable=true)`, API.md §1's existing rule for side-effect-free reads), no Custom Permission required (§30) |

No DTO shape defined elsewhere in this platform is altered by this document — the new method's output is the only new contract surface.

---

## 35. Testing Strategy

- **`oiGraphCanvas`/`oiGraphNode` Jest tests**: pure prop-in/event-out assertions (§3, §4, §5) — a fixture with a synthetic, never-registered `typeKey` must render the generic fallback (§20) without error, the direct test of this round's "unknown future node types" mandate.
- **View-state module unit tests** (`graphViewState.js`, plain JS, testable with no LWC harness at all): the diamond-shared-descendant scenario named in §13 as the required, non-optional case; a hub-node pagination sequence (§15) asserting cursor independence across two simultaneously-paginating nodes; the working-set-ceiling boundary (§26) asserting the explicit-stop state fires rather than a silent no-op or a silent eviction of in-view nodes.
- **Container component tests**: mock the Apex layer entirely (existing Jest convention, CodingStandards §10) — assert the *right* call is made for the *right* user action per §9's table (e.g., selecting a search result calls `getGraphFragment` with `hopDepth: 0`, never a neighborhood-fetching depth — a direct test of §8's separation-of-concerns claim, not just a prose assertion of it).
- **Accessibility**: an automated axe-core-style pass (or equivalent) against a rendered fixture graph, plus a manual keyboard-only-navigation pass through expand/collapse/select as part of the review checklist (CodingStandards §14) — accessibility claims in §28 are only as good as a test that actually exercises them.

---

## 36. Package Readiness

- **No hardcoded metadata assumptions**: every rendering decision resolves through the registry (§20/§21) with a generic fallback — a subscriber org with zero configured Domain Type Registry rows still gets a fully functional, generically-styled graph, satisfying `CLAUDE.md` §Metadata Assumptions exactly as every other subsystem in this platform is required to.
- **Static resource compliance**: the vendored layout library (§32) is pinned, licensed, and CSP-audited before use — CodingStandards §11's existing rule, with this document naming the concrete component it applies to.
- **FlexiPage/Lightning App packaging**: `oiGraphExplorer` ships as the single top-level component hosted in the package's Lightning App (Architecture §9's existing shell model) — no new packaging mechanism introduced.
- **Namespace safety**: no field-API-name string literals for *scanned* (customer) metadata appear anywhere in this document's component contracts — every field the UI touches is either this platform's own strongly-typed DTO shape or an opaque `typeKey`/`nodeKey` string, consistent with Architecture §15's existing namespace-safety rule.

---

## 37. Extension Points

| Extension point | Where introduced | What it enables without a UI-architecture change |
|---|---|---|
| Presentation Type Registry, resolved at runtime (§0, §20/§21) | Resolved ambiguity | A new metadata type styles itself via Custom Metadata alone — zero LWC deploy |
| Container/presentational split (§3) | New, this document | A future alternate Canvas rendering technology (§32) swaps in behind the same presentational contract, touching no container logic |
| Working-set ceiling as a named, explicit state (§26, §29) | New | A future "graph too large, here's why" UX (e.g., a suggested collapse target) can build on an already-honest signal rather than inventing one |
| Viewport Mini-map / Frontier Summary split (§24) | New | Either half can evolve independently — e.g., the Frontier Summary gaining type-specific icons requires no change to the Viewport half at all |
| Re-center-without-losing-breadcrumb affordance (§23) | New | A future "compare two centers side by side" feature has an existing navigation primitive to build from |
| Impact-result-as-expand unification (§7) | New | Any future feature that reveals a curated (non-1-hop) node set can reuse the same reference-counting visibility model rather than inventing a second one |
| AI Query Translator sitting above Search + Dependency Engine ([SearchEngine.md §27](SearchEngine.md#27-ai--natural-language-search-extension)) | Inherited | A natural-language "show me..." feature composes existing Search/Graph/UI primitives — this document's container/presentational split means such a feature only ever needs to drive `oiGraphExplorer`'s existing public actions, never reach into the Canvas |

---

## 38. Risks

| Risk | Why it could happen | Mitigation |
|---|---|---|
| **The reference-counting algorithm (§13) is implemented against `supportingAncestors` alone, without the separate `revealedSet` tracking** — the single highest-severity risk in this document | §13's subtlety is real and easy to miss under normal development pressure; the bug it causes (over-eager or under-eager node removal on collapse) is silent and only surfaces on graphs with genuinely shared/cyclic structure, which may not appear in casual manual testing | The diamond-shaped-subgraph test case (§35) is named as required, not optional, specifically because this failure mode would pass every "simple tree-shaped" manual test while being wrong on real metadata graphs |
| **Hub-node type-grouping (§26) still produces a visually noisy result for a node connected to many *different* types in large counts** | Type-grouping helps when one or two types dominate a hub's fan-out; a hub genuinely connected to a wide spread of types across many instances each has no single grouping axis that fully resolves the noise | Named honestly as a partial mitigation, not a complete solution — the working-set/pagination controls (§15, §26) remain the backstop; a more sophisticated hub-specific layout (e.g., a dedicated "expand as list" mode for extreme hubs) is not designed here and is flagged as an open question (§41) |
| **The registry-fetch-once-per-session cache (§10, §20) goes stale within a long-lived tab session** if an admin changes Domain Type Registry configuration mid-session | Custom Metadata changes don't push-notify open client sessions | Accepted, low-severity: styling is cosmetic, not correctness-affecting; a full page refresh (a normal, expected action, not a workaround) picks up the change. Not solved with a live-invalidation mechanism, consistent with [GraphEngine.md §9](GraphEngine.md#9-incremental-graph-loading)'s own explicit deferral of live push notification for a similarly low-stakes staleness window |
| **A future contributor adds an Apex call inside `oiGraphCanvas` or `oiGraphNode`** "just this once," for a feature that seems to need it | The container/presentational rule (§3) is enforced by convention and code review, not a build-time technical guard — LWC has no native mechanism preventing a presentational component from importing an Apex method | Named as a process control, honestly, consistent with how this platform has already flagged equivalent Apex-layer risks (e.g., [GraphRepository.md §21](GraphRepository.md#21-risks)'s Selector-delegation risk) — a code-review checklist item (CodingStandards update, §36), not a runtime safeguard |

---

## 39. Trade-offs

| Trade-off | Cost accepted | Benefit gained |
|---|---|---|
| Hybrid radial-graph over a pure tree (§18) | More complex layout logic than a simple hierarchical tree render | Topological honesty — no hidden or duplicated shared/cyclic relationships, a correctness property, not just an aesthetic one |
| Hybrid radial-graph over pure force-directed (§18) | Less "naturally organic" layout than an unconstrained force simulation | A stable, centered spatial mental model across many expand/collapse actions — directly serving this document's "clarity over decoration" priority |
| SVG over Canvas/WebGL (§32) | Real-DOM per-node cost, in principle higher than a bitmap surface at very large element counts | Accessibility, hit-testing, and styling integration essentially for free — and this platform's own bounded-scale guarantee means the "very large element counts" cost never actually materializes |
| Edges never componentized, nodes always are (§5, §6) | An asymmetric rendering architecture — two different techniques for the two kinds of graph elements | Each technique matched to what its element actually needs (rich per-instance interactivity for nodes; cheap, high-volume rendering for edges) rather than one uniform technique poorly suited to one of the two |
| Working-set ceiling as an explicit user-facing stop, not a silent eviction (§26) | The user occasionally has to take an action (collapse something) mid-exploration rather than the UI "just handling it" invisibly | Never silently removes a node the user is actively relying on being visible — an honesty property this document treats as non-negotiable, consistent with the same principle already established for search truncation |
| Impact-result-driven nodes unified into the expand reference-counting model, not a second visibility system (§7) | Impact Analysis results can't be visually distinguished from "just an expand" at the view-state level without an additional flag | One visibility/collapse algorithm to build, test, and reason about, instead of two independently-maintained ones |

---

## 40. Alternatives Considered

- **Visualization strategy** — (a) hierarchical tree (rejected — §18, wrong data structure for this product's actual data); (b) pure undirected force-directed graph (rejected — §18, poor fit for the mandated egocentric interaction model, degrades badly exactly at the hub-node failure mode this round names); (c) **chosen** — hybrid graph-topology/radial-layout. Full analysis: [ADR-0019](ADR/0019-hybrid-radial-graph-visualization.md).
- **Rendering technology** — (a) Canvas 2D (rejected — §32, forfeits native accessibility/hit-testing for a scale-cost benefit this platform's bounded-fetch guarantees make moot); (b) WebGL (rejected — same reasoning, with even more reimplementation cost for accessibility, unjustified at this platform's actual scale); (c) a full opinionated graph-visualization framework (rejected — §32, would fight this document's own already-designed architecture for control of concerns — rendering, data-binding, interaction — this document has already specifically solved); (d) **chosen** — SVG plus a narrowly-scoped, vendored layout-math library. Full analysis: [ADR-0020](ADR/0020-svg-rendering-vendored-layout-library.md).
- **Edge componentization** — (a) one LWC instance per edge, mirroring nodes (rejected — §6, real, avoidable per-instance overhead for capability the interaction model doesn't need); (b) **chosen** — Canvas-owned SVG paths with event delegation.
- **Presentation Type Registry delivery** — (a) a build-time-baked static resource (rejected — §0, would require a package push for every new type's styling, contradicting this platform's own "new type = Custom Metadata, zero deploy" promise elsewhere); (b) **chosen** — runtime Custom Metadata read, fetched once, client-cached.
- **Mini-map** — (a) one always-server-backed widget (rejected — §24, needlessly costs a round-trip for the purely local navigation half); (b) one always-client-only widget (rejected — loses the genuinely useful frontier-preview capability the existing API was built for); (c) **chosen** — two explicitly distinct halves in one component.
- **Impact-result visibility handling** — (a) a second, parallel visibility-tracking mechanism specific to impact results (rejected — §7, unnecessary duplication of an already-correct model); (b) **chosen** — unify into the same reference-counting model as ordinary expand.

---

## 41. Open Questions

1. **Should the hub-node type-grouping affordance (§26) escalate to a dedicated "expand as list" mode for extreme fan-out**, rather than relying on grouping plus pagination alone? Flagged honestly in §38 as a partial mitigation; not designed here because no concrete fan-out distribution data from a real subscriber org exists yet to design against (`CLAUDE.md`: never invent missing business requirements ahead of evidence).
2. **Should re-layout on collapse be animated** (freed angular space smoothly redistributing) **or static** (§17 currently assumes static as the simpler v1 choice)? A genuine UX-polish question with no correctness stakes either way — deferred to whoever implements against this document, not decided here.
3. **Does the Viewport Mini-map (§24) need its own separate zoom/pan controls**, or is it purely a read-only indicator? Currently designed as read-only (simpler, and consistent with most "you are here" mini-map conventions elsewhere), but click-to-jump-there on the mini-map itself is a plausible, undesigned future affordance.
4. **Should `Max_Canvas_Working_Set__c` (§26) be a single global default, or admin-tunable per Custom Permission tier** (e.g., a Power User allowed a larger working set than a Viewer)? No concrete need identified yet; a single global default (via `OI_Settings__mdt`, consistent with every other numeric ceiling in this platform) is the simpler starting point.
5. **Should the re-center-without-losing-breadcrumb affordance (§23) support branching** (multiple divergent explorations from one earlier point, not just a linear trail)? Out of scope for this document — the trail is deliberately linear, matching the simplicity `CLAUDE.md`'s Core Principles favor; a branching history is a real but currently unrequested feature.

---

## 42. Object-Relationship Lane Layout (Object Analyze Mode Only)

Formalized in [ADR-0023](ADR/0023-object-relationship-lane-layout.md); added here per §0's newest finding. **Scope, stated once and binding for this entire section**: everything below applies to Object analyze mode's canvas only. Field mode and Record mode keep using §17/§18's radial canvas, completely unmodified — no getter, filter, or view-state field this section describes is read by, or affects, either of those two modes.

### 42.1 Why a Second Layout, Concretely

Object analyze mode's product question — "how is this Object structurally connected to other Objects?" — is narrower than the general egocentric-neighborhood question §17/§18 designs for. Reusing the radial canvas for it produces two confirmed, present-day defects: non-Object node types (ApexTrigger/Flow via `EXECUTES_ON`, PermissionSet/ApexClass via `GRANTS_ACCESS_TO`) render as cards despite being irrelevant to an object-structure question, and the ring layout has no directional (incoming vs. outgoing) framing at all. §42.2–§42.7 are the direct fix, scoped narrowly rather than generalized into §17/§18.

### 42.2 Presentation Transform — `objectRelationshipView.js`

A new, dependency-free pure module (no Apex import, no registry import — unit-testable exactly like `graphViewState.js`, with no LWC test harness required). Input: the container's already-styled, already-fetched working set (`nodes`, `edges`) plus `centerNodeKey`. Output: `{ rootObject, incomingRelationships[], outgoingRelationships[], selfRelationships[], counts }`.

**Derivation, precisely**:
1. **Card filter**: only `typeKey === SalesforceMetadata.CustomObject` nodes become renderable cards. This is the structural fix for §42.1's type-leakage problem — every other node type stays in the working set (available to the Intelligence Panel and drilldowns via their own, independent service calls) but is never rendered on this canvas.
2. **Ownership index**: from every `HAS_FIELD` edge, `fieldKey -> ownerObjectKey` — built unconditionally here, not reused from `oiGraphCanvas`'s registry-gated field-absorption map, which answers a different, narrower question for a different canvas.
3. **Relationship extraction**: for every `LOOKUP_TO`/`MASTER_DETAIL_TO` edge (edge source = the field's own key, edge target = the referenced object — per `OI_FieldScanner.cls`'s own edge construction), resolve the owning object via the index in step 2. Defensively skip if any side isn't in the current node set (the same "dangling reference" discipline `graphRelationshipFilter.js` already applies elsewhere).
4. **Center-anchoring**: keep a relationship iff the center object is the owner (outgoing), the referenced object (incoming), or both (self). A relationship between two non-center objects that both happen to be in the working set is deliberately excluded — this view answers "what does *this* object relate to," not "everything currently loaded."
5. **Aggregation**: group by the `(ownerObjectKey, referencedObjectKey)` pair into one connector — `{counterpartObject, direction, fields[], relationshipCount, primaryRelationshipType, isSystemRelationship}`. `primaryRelationshipType` is Master-Detail if any field in the group is one; connector-level `isSystemRelationship` is true only if *every* field in the group classifies as System (§42.3) — a connector must never look hidden-by-default merely because one of several fields sharing it happens to be a system field. A polymorphic field (e.g. `WhatId`) correctly produces one row per referenced object, by construction — expected, not a duplicate.
6. **Deterministic bounding**: each lane sorted by `relationshipCount` desc, then counterpart label asc — never force/random positioning. The first 6 connectors per lane render initially; the remainder surface via a client-side "show N more" (mirroring `oiGraphCanvas`'s existing `expandedClusters` precedent, §26) — zero new fetch, since everything is already within the existing bounded working set.
7. **Center card metadata**: Standard vs. Custom is derived as `secondaryKey.endsWith('__c')` — `OI_NodeSummary` never carries the `attributes` blob (GraphEngine.md's lazy-attribute-load rule), so this mirrors the same no-new-fetch convention `oiNodeDetailPanel.js` already uses for equivalent facts elsewhere.

### 42.3 System vs. Business Relationship Classification

A field-level classification, not a new registry concept: exact match of the field's own API name — derived from the field node's own `secondaryKey` (e.g. `"Account.OwnerId"` → `"OwnerId"`), never `edge.viaFieldApiName`, which despite its name is populated from the edge's stored `relationshipName` attribute (`OI_GraphTraversal.cls`'s `extractViaFieldApiName`) and is therefore the *relationship* name (`"Owner"`, `"CreatedBy"`), not the field API name — a real, live-org-confirmed mismatch this implementation corrected during validation, not a hypothetical concern — against the fixed set `{OwnerId, CreatedById, LastModifiedById}` — the universal, platform-standard audit-field names present on effectively every SObject, not org-specific configuration, so hardcoding this short list does not violate `CLAUDE.md`'s "never assume org metadata" rule (it is the same category of platform constant as a `typeKey` literal). The canvas exposes a **Business / System / All** toggle, defaulting to Business-only — never a silent, permanent hide (§14 in the original mandate this ADR responds to; consistent with this document's existing "no silent caps" principle, §26).

### 42.4 Connector Detail and Navigation

Clicking an aggregated connector opens `oiRelationshipConnectorDetail` (new, container): source object, field(s), relationship type, target object, direction, and Open Source/Field/Target actions via the existing `OI_GraphController.getNavigationTarget` + `c/metadataNavigation` — no new navigation mechanism, no hardcoded Setup URLs. This is a distinct, simpler surface from `oiIntelligenceDrilldown` (a paged, searchable list of *many* connections for one category) — one connector's own detail has no paging/search need.

### 42.5 "Explore From Here"

A neighbor card's explicit action re-centers the graph on that object — implemented as a thin wrapper around `oiGraphExplorer`'s existing `selectAndCenter`, identical to a fresh search selection (§8): a full view replacement, not a partial rewind, consistent with this document's existing re-centering semantics (§23).

### 42.6 Legend and Emphasis

The legend for this canvas covers Lookup / Master-Detail / Self-Relationship / System Relationship only — deliberately not "Executes On" or "Grants Access To," which are Intelligence Panel concepts (Automation/Security sections), not Object-relationship-graph concepts, per §42.1's scope. Hover/select emphasis is simpler than the radial canvas's ancestry-path walk (§4): since every connector here is, by construction, exactly one relationship away from center, emphasis reduces to "the focused card and its own connector," with no path-walking needed. Emphasis persists on click/select, not hover alone (this document's existing accessibility principle, §28, restated for this layout).

### 42.7 Accessibility, Determinism, and Performance

Every card, connector, and toggle is keyboard-navigable with an aria-label composed from real data ("Opportunity references Account through AccountId, Lookup") — never a raw internal `typeKey`, per §28's existing rule. Layout is fully deterministic given the same working set (§42.2 step 6) — no force-relaxation pass, unlike §17's ring layout, since a lane model has no equivalent angular-crossing problem to solve. No new Apex call, traversal, or query is introduced anywhere in this section — every input is already present in the working set §9's existing `getGraphFragment(hopDepth: 2)` call for Object mode already fetches, consistent with §25/§27's existing performance discipline.

`view` (the derived lane model) is memoized by reference identity on `(nodes, edges, centerNodeKey)` — live-org validation against a heavily-customized Account object (hundreds of relationship-bearing fields within its own bounded 2-hop working set) showed this matters concretely: the template reads the derived diagram from well over a dozen distinct bindings in one render pass, and an unmemoized transform meant re-running the full derivation that many times per render. `oiGraphExplorer.js`'s own `allCanvasNodes`/`allCanvasEdges` getters are memoized the same way, since `objectRelationshipSummary` (§42.8) reads them independently of the canvas.

### 42.8 Real Connectors, Not Detached Labels

A visual-acceptance correction, superseding the plainer connector treatment §42.2–§42.6 originally described: connectors are drawn as actual SVG paths joining card to card (a "trunk" per lane — each row branches horizontally off its own card into one shared vertical spine, which makes a single final approach into the center card, keeping routing orthogonal and non-crossing regardless of how many rows converge), with an arrowhead marker and a label rendered as an HTML badge positioned directly on the line — never a bare `<span>` floating beneath a card with no visible line to anchor it. Master-Detail renders as a visibly heavier stroke than Lookup (never color alone); System relationships render dashed, matching the legend exactly. A connector click always opens `oiRelationshipConnectorDetail` — there is no separate inline "expand this aggregate" affordance, since the detail surface already lists every aggregated field.

Self-relationships render as their own small "shadow" card labelled "{Object} (Self)", captioned "SELF RELATIONSHIP / {Object} references {Object}" above it, joined to the real center card by a rounded loop — never a bare label with nothing to visually connect it back to the object it describes.

The Intelligence Panel's Relationships section is, for an Object-centered selection, a curated fixed set — Incoming/Outgoing Lookups, Incoming/Outgoing Master-Detail, Self Relationships, Referenced Objects, Referencing Objects — never raw internal edge-type taxonomy (`HAS_FIELD` is schema membership, not an object-to-object relationship, and is deliberately never shown here; it already powers the Fields section's own count). The four Lookup/Master-Detail counts come from the same `getNodeDetail` counts the panel already had (always-complete, independent of canvas pagination); Self/Referenced/Referencing are distinct-object counts the container computes once via `objectRelationshipView.js` over the same working set the canvas uses (`oiGraphExplorer.js`'s `objectRelationshipSummary`, passed down as a prop) and are simply omitted, never fabricated as zero, when not yet available. Field/Record modes are unaffected — they keep the pre-existing generic per-edge-type relationship rows.

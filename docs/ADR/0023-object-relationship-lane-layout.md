# ADR-0023: Object-Relationship Lane Layout for Object Analyze Mode, Coexisting with ADR-0019

## Status
Accepted — scoped exception to [ADR-0019](0019-hybrid-radial-graph-visualization.md), which remains unchanged and authoritative for Field Analyze mode, Record Analyze mode, and any future general-purpose graph exploration.

## Context
ADR-0019 chose a hybrid graph-topology/radial-layout strategy as *the* visualization for the Graph UI subsystem, and [GraphUI.md §3](../GraphUI.md#3-component-architecture) wires that strategy into one shared, generic `oiGraphCanvas` reused by all three of `oiGraphExplorer`'s analyze modes (Object/Field/Record). That sharing was appropriate when the canvas's job was "render whatever a bounded BFS from any centered node returns" — a genuinely mode-agnostic question.

Object Analyze mode asks a narrower, different question in practice: "how is this Object structurally connected to other Objects?" Two concrete problems follow directly from reusing the generic radial canvas for that specific question, verified against the actual traversal and scanner code, not assumed:

1. **Type leakage.** `OI_GraphTraversal.collectRing` walks edges undirected with no type filter. An Object-centered 2-hop fetch (`oiGraphExplorer.js`'s `HOP_DEPTH_BY_MODE.Object = 2`) therefore genuinely surfaces ApexTrigger/Flow nodes (via `EXECUTES_ON` edges, `OI_ApexTriggerScanner.cls`/`OI_FlowScanner.cls`) and PermissionSet/ApexClass nodes (via `GRANTS_ACCESS_TO`, `OI_PermissionSetScanner.cls`) on a canvas whose product question is object-to-object structure, not "everything within two hops." The existing `relationshipOnlyView` declutter pass in `oiGraphExplorer.js` only prunes plain data Field nodes — it was never designed to (and does not) address this.
2. **No directional framing.** The radial canvas's ring-by-hop-distance layout has no notion of "objects that reference this one" vs. "objects this one references" — a distinction Object Analyze mode's own product question depends on, and one a symmetric egocentric ring cannot express without becoming a different layout entirely.

Both problems are specific to the "single node type, directional relationship inventory" question Object mode asks. They do not generalize to Field mode (browsing one object's own fields — a fundamentally different, single-object-scoped question) or Record mode (a live record hierarchy fragment, ADR-0021), and this ADR does not touch either.

## Decision
Introduce a second, narrowly-scoped visual arrangement — directional lanes (objects referencing the center on the left, objects the center references on the right, self-relationships in a dedicated area below, center fixed) — for **Object analyze mode only**. Concretely:

- A new pure presentation-transform module, `objectRelationshipView.js`, derives lanes from the already-fetched, already-bounded working set (no new Apex call, no new traversal): it keeps only Object-typed nodes as renderable cards, resolves each `(Object) --HAS_FIELD--> (Field) --LOOKUP_TO|MASTER_DETAIL_TO--> (Object)` chain into a direct object-to-object relationship, and classifies each as incoming/outgoing/self relative to the centered object.
- A new presentational component, `oiObjectRelationshipCanvas`, renders that derived model. `oiGraphCanvas` is not modified, extended with a "lane mode" flag, or otherwise touched.
- `oiGraphExplorer` gains one new conditional branch (render the new canvas when `analyzeMode === 'Object'`) alongside its existing, completely unmodified Field/Record branch.
- The underlying directed-graph data model (ADR-0001), traversal algorithm (`OI_GraphTraversal`), reference-counted visibility model (GraphUI.md §13), and registry-driven styling (ADR-0011) are entirely untouched — this is a presentation-layer fork over the same data and the same services, not a data-model or traversal change.

ADR-0019's radial layout is not deprecated, weakened, or superseded by this decision. It remains the correct, unchanged answer for Field mode, Record mode, and any future feature that needs a general, multi-type egocentric neighborhood view.

## Consequences
- **Positive**: Object Analyze mode's canvas now answers its actual product question directly — object-to-object structure, correctly filtered and directionally framed — without regressing or complicating the general-purpose explorer that Field/Record and any future multi-type exploration still depend on.
- **Positive**: the fork is structural, not conventional — `oiGraphExplorer`'s existing Field/Record branch, filter state, and getters are untouched by this change, so there is no code path where an Object-mode-only change could silently alter Field/Record rendering.
- **Negative**: two layout algorithms now exist in the Graph UI subsystem instead of one. Accepted because they answer genuinely different questions (a bounded, multi-type egocentric neighborhood vs. a single-type directional relationship inventory) — the same category of reasoning ADR-0019 itself already used to reject forcing one visualization model onto data shapes it doesn't fit.
- **Negative**: `objectRelationshipView.js`'s object-to-object relationship derivation (composing `HAS_FIELD` + `LOOKUP_TO`/`MASTER_DETAIL_TO` edges) is logic that exists nowhere else today and must be kept correct independently of `oiGraphCanvas`'s own, unrelated field-absorption logic (which serves a different rendering purpose and is deliberately not reused here, to avoid coupling two components that now have different jobs).

## Alternatives Considered
- **Add a "lane mode" flag to `oiGraphCanvas` itself** — rejected: `oiGraphCanvas` is already a large, generic, multi-type rendering surface (ring layout, clustering, field absorption); folding a second, structurally different layout model into the same component violates single-responsibility and risks regressing Field/Record rendering paths that share the same file.
- **Generalize ADR-0019's ring-by-hop-distance model to also produce lanes** — rejected: ring placement (radial distance) and incoming/outgoing side placement (a directional, not distance-based, question) are different spatial models; forcing one algorithm to produce both would make the simpler, correct case (rings) harder to reason about for no shared benefit.
- **Do nothing, rely on the existing declutter pass** — rejected: the declutter pass only ever addressed plain data Fields; it does not and cannot address ApexTrigger/Flow/PermissionSet/ApexClass leakage or the missing directional framing, both confirmed as real, present-today behavior, not hypothetical.

## Related
[ADR-0019](0019-hybrid-radial-graph-visualization.md) (the layout decision this ADR scopes an exception to, for one analyze mode only — not superseded); [ADR-0001](0001-graph-data-model-as-core-abstraction.md) (the underlying graph model, unchanged); [ADR-0011](0011-generic-node-edge-typing-via-domain-registry.md) (registry-driven styling, unchanged, still resolved at the container level for the new canvas); [ADR-0022](0022-hierarchy-accelerator-separate-persistence-lane.md) (the most recent precedent for a scoped, justified divergence from ADR-0019's default rather than a silent contradiction of it); [GraphUI.md](../GraphUI.md) §0 Round 8, §42.

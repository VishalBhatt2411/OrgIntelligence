# ADR-0015: Discovery Model as a Graph-Blind Intermediate Representation

## Status
Accepted — elaborates [ADR-0001](0001-graph-data-model-as-core-abstraction.md) and [ADR-0011](0011-generic-node-edge-typing-via-domain-registry.md); corrects a claim in [GraphEngine.md](../GraphEngine.md) §7 (pre-correction)

## Context
The original description of the Metadata Scanner ([Architecture.md](../Architecture.md) §6, [GraphEngine.md](../GraphEngine.md) §7) had each per-type Scanner (`OI_FlowScanner`, etc.) translating a discovered Salesforce entity directly into an "already-generic" `UpsertNode{typeKey: "SalesforceMetadata.Flow", ...}` Mutation. That required the Scanner to know the Graph Engine's `typeKey` convention — graph vocabulary, not metadata vocabulary — which is a narrower version of exactly the coupling [ADR-0011](0011-generic-node-edge-typing-via-domain-registry.md) already argued against for the *engine* side of this seam. [MetadataScanner.md](../MetadataScanner.md) makes explicit what should have been true all along: the Scanner's job is metadata discovery, full stop, and it must not know Graph Nodes or Edges exist.

## Decision
Introduce a **Discovery Model** (`OI_DiscoveryBatch`, `OI_DiscoveredComponent`, `OI_DiscoveredRelationship` — [MetadataScanner.md](../MetadataScanner.md) §5) as the Scanner's actual output: a shape expressed entirely in Salesforce's own vocabulary (`componentKind`, `relationshipKind`), with no `typeKey`, no `nodeKey`/`edgeKey`, and no reference to any Graph Engine class. A new, single component — the **Mutation Generator** (`OI_MutationGenerator`, [MetadataScanner.md](../MetadataScanner.md) §15) — is the only thing downstream of the Scanner permitted to know both vocabularies; it consumes Discovery Batches and produces the Mutations `OI_GraphBuilder` already expected ([GraphEngine.md](../GraphEngine.md) §7), calling `OI_GraphEngine` exclusively, per the existing facade rule ([ADR-0013](0013-graphengine-facade.md)).

## Consequences
- **Positive**: the Scanner can be built, tested, and reasoned about with zero Graph Engine dependency — a `OI_FlowScannerTest` needs no fake `OI_GraphEngine`, only fake Adapters.
- **Positive**: the Discovery Model becomes a reusable artifact independent of graph construction — a future metadata-export, cross-org-diff, or AI feature can consume it directly ([MetadataScanner.md](../MetadataScanner.md) §18, §20) without a graph existing at all.
- **Positive**: the blindness is now symmetric and named on both sides of the seam — the Graph Engine doesn't know Salesforce vocabulary ([ADR-0011](0011-generic-node-edge-typing-via-domain-registry.md)), and the Scanner doesn't know graph vocabulary (this ADR); exactly one component, the Mutation Generator, is allowed to know both, and it is the *only* place a reviewer needs to check for a vocabulary leak in either direction.
- **Negative**: one additional pipeline stage and one additional data shape versus the Scanner emitting Mutations directly — accepted for the isolation and reuse benefits above.
- **Negative**: retire-detection (noticing a component that no longer exists in Salesforce) cannot be a Scanner decision, since it requires comparing against current graph state — relocated to the Mutation Generator, which needs read access to `OI_GraphEngine` for exactly this purpose ([MetadataScanner.md](../MetadataScanner.md) §3.2, §15). This is a deliberate, narrow, one-directional read-coupling, not a general permission for the Mutation Generator to reach into the Graph Engine's internals.

## Alternatives Considered
- **Status quo — Scanner emits Mutations directly** — rejected: this is precisely the coupling being corrected.
- **A single unified Scanner+MutationGenerator component** — rejected: reintroduces graph knowledge into the Scanner, defeating the purpose outright.
- **Retire-detection inside the Scanner** — rejected: would require the Scanner to query the graph, violating blindness directly; the alternative of retire-detection inside `OI_GraphBuilder` was also considered and rejected because the Builder would then need its own "what's the complete expected set" cross-referencing logic duplicating what a full Discovery Batch already represents — the Mutation Generator, sitting exactly at the boundary, is the natural, minimal place for this decision.
- **A `componentKind → typeKey` explicit lookup table** instead of a deterministic naming convention — a live, not-dismissed alternative; not adopted now because no concrete need for many-to-one mapping exists yet, and the convention avoids a runtime dependency on Custom Metadata being correctly populated for basic ingestion to succeed ([MetadataScanner.md](../MetadataScanner.md) §15, §24).

## Related
[MetadataScanner.md](../MetadataScanner.md) §0, §1, §5, §15; [GraphEngine.md](../GraphEngine.md) §7; ADR-0001; ADR-0011; ADR-0013.

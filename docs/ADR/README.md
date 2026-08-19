# Architecture Decision Records

Index of ADRs for the Salesforce Org Intelligence Platform. Each record captures a significant, hard-to-reverse architectural choice: the context that forced it, the decision, its consequences (including accepted trade-offs), and the alternatives rejected. See [../Architecture.md](../Architecture.md) for how these decisions fit into the overall system.

| # | Title | Status |
|---|---|---|
| [0001](0001-graph-data-model-as-core-abstraction.md) | Graph Data Model as the Core Abstraction | Accepted (amended by 0011) |
| [0002](0002-hybrid-custom-object-big-object-graph-persistence.md) | Hybrid Custom Object + Big Object Graph Persistence | Accepted |
| [0003](0003-layered-architecture-with-dependency-inversion.md) | Layered Architecture with Service/Selector/Repository/Adapter Separation | Accepted |
| [0004](0004-queueable-chain-scan-orchestration.md) | Queueable-Chain Scan Orchestration (over a Single Batch Job) | Accepted |
| [0005](0005-second-generation-managed-package.md) | Second-Generation Managed Package for AppExchange Distribution | Accepted |
| [0006](0006-apex-boundary-security-model-for-app-internal-data.md) | Apex-Boundary Security Model for Application-Internal Data | Accepted |
| [0007](0007-sosl-search-behind-abstracted-service.md) | SOSL-Based Search Behind an Abstracted Search Service | Accepted |
| [0008](0008-lightweight-client-state-management.md) | Lightweight Client State Management (No Heavy State Library) | Accepted |
| [0009](0009-incremental-scanning-via-checksum-diffing.md) | Incremental Metadata Scanning via Checksum Diffing | Accepted |
| [0010](0010-three-layer-caching-with-neighborhood-invalidation.md) | Three-Layer Caching Strategy with Neighborhood-Scoped Invalidation | Accepted |
| [0011](0011-generic-node-edge-typing-via-domain-registry.md) | Generic Node/Edge Typing via an Externalized Domain Type Registry | Accepted — amends 0001 |
| [0012](0012-graph-repository-storage-gateway.md) | GraphRepository as the Sole Storage Gateway | Accepted — elaborates 0002 |
| [0013](0013-graphengine-facade.md) | GraphEngine Facade — Single Public Entry Point | Accepted — elaborates 0003 |
| [0014](0014-immutable-node-edge-versioning.md) | Immutable Node/Edge Versioning Model | Accepted — elaborates 0001 |
| [0015](0015-discovery-model-graph-blind-scanner.md) | Discovery Model as a Graph-Blind Intermediate Representation | Accepted — elaborates 0001, 0011 |
| [0016](0016-repository-atomic-commit-and-optimistic-concurrency.md) | Atomic Version Commit and Optimistic Concurrency in GraphRepository | Accepted — elaborates 0012, 0014 |
| [0017](0017-search-provider-abstraction-record-search-outside-graph.md) | Search Provider Abstraction; Record Search Kept Outside the Graph | Accepted — elaborates 0007 |
| [0018](0018-denormalized-parent-key-for-search-scoping.md) | Denormalized `parentKey` for Object-Scoped Search Filtering, Instead of Traversal | Accepted — elaborates 0001, 0011 |
| [0019](0019-hybrid-radial-graph-visualization.md) | Hybrid Graph-Topology, Radial-Layout Visualization — Not a Literal Tree | Accepted — elaborates 0001 |
| [0020](0020-svg-rendering-vendored-layout-library.md) | SVG-Based Rendering with a Narrowly-Vendored Layout Library, Not Canvas/WebGL | Accepted |
| [0021](0021-record-analysis-deferred-outside-metadata-graph.md) | Record Analysis Deferred, and Kept Architecturally Outside the Metadata Graph When Built | Proposed — amended by 0022 |
| [0022](0022-hierarchy-accelerator-separate-persistence-lane.md) | Hierarchy Accelerator as a Structurally Separate Persistence Lane | Proposed — amends 0021 |

## When to add a new ADR

Add one when a decision is expensive to reverse, affects more than one engine/service boundary, or rejects a plausible alternative for a non-obvious reason. Don't add one for routine implementation choices already covered by [CodingStandards.md](../CodingStandards.md).

## Template

```markdown
# ADR-XXXX: <Title>

## Status
Proposed | Accepted | Superseded by ADR-YYYY

## Context
<the forcing constraints>

## Decision
<what was decided>

## Consequences
<positive and negative, explicitly>

## Alternatives Considered
<what was rejected, and why>

## Related
<links to Architecture.md sections, other ADRs, DataModel.md, etc.>
```

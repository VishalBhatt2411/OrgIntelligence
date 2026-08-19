# ADR-0004: Queueable-Chain Scan Orchestration (over a Single Batch Job)

## Status
Accepted

## Context
The Metadata Scanner must scan ~15 different metadata types, each via a different API (Describe, Tooling, Metadata) with different call shapes, different rate-limit characteristics, and different failure modes. A scan must never be synchronous (Architecture §1 — "never load an entire org"), and a failure scanning one metadata type must not abort the entire run.

## Decision
Orchestrate the scan as a **chain of Queueable jobs**, one hop per metadata type (or per chunk within a large type), driven by `OI_ScanOrchestratorQueueable` reading `OI_Metadata_Type_Config__mdt` to decide what runs next and with what batch size. Very large individual metadata types may additionally use Batch Apex *within* their own scanner for record-level chunking, but the top-level orchestration between types is Queueable chaining, not one monolithic Batch job.

## Consequences
- **Positive**: a failure in one scanner (e.g., a Tooling API error scanning Flows) is caught, logged, and recorded against that `OI_Scan_Task__c` without preventing the next scanner in the chain from running — directly satisfies the failure-isolation goal.
- **Positive**: different metadata types can have different priority/cadence (Architecture §6 — "rescanning Apex more often than Reports") because each hop is an independent unit of work reading its own config, not a single fixed `execute`/`finish` pair.
- **Positive**: Queueable chaining composes cleanly with async callouts (Tooling/Metadata API), which Batch Apex's `execute` context handles less naturally at scale across heterogeneous call types.
- **Negative**: Queueable chains are still subject to the org's daily async Apex job limits and a maximum chain depth consideration in some contexts; mitigated by the self-imposed API budget (Architecture §17) and by not chaining more hops than metadata types configured.
- **Negative**: slightly more orchestration code than a single Batch job — accepted for the failure-isolation and per-type-cadence benefits.

## Alternatives Considered
- **Single Batch Apex job over "all metadata"** — rejected: a `scope` in Batch Apex is homogeneous; heterogeneous per-type API calls and failure isolation don't fit the Batch `execute(scope)` model without significant internal branching that would defeat the Strategy pattern (ADR-0003's rationale).
- **Fully synchronous scan** — rejected outright by Architecture §1/§17 and CPU/callout governor limits at any realistic org size.

## Related
Architecture.md §6, §17; DataModel.md §2.1–§2.2; [MetadataScanner.md](../MetadataScanner.md) (full subsystem spec — this ADR's orchestration model is unchanged by it, but every reference to "the scanner" below should be read against that document's corrected pipeline: Scanner → Discovery Model → Mutation Generator, per [ADR-0015](0015-discovery-model-graph-blind-scanner.md)).

## Amendment — Sprint 9.1 (Batch Apex Realizes the Pre-Approved Allowance)

A real Developer Edition sandbox scan (Sprint 9 validation) proved the "maximum chain
depth consideration" flagged in Consequences above was not merely theoretical: Sprint
8/9's implementation chunked a large type's component/relationship ingestion via
*further Queueable hops nested within the same chain* that also advances between types.
This broke this ADR's own stated mitigation ("not chaining more hops than metadata types
configured") — a single oversized type (240 `CustomObject` components at a chunk size of
60) could exhaust the entire run's chain-depth budget by itself, and the scan never
reached `CustomField`.

This is not a reversal of this ADR's Decision. The Decision already anticipated exactly
this scenario: *"Very large individual metadata types may additionally use Batch Apex...
for record-level chunking."* Sprint 9.1 realizes that allowance — at the Orchestrator
layer (`OI_ScanComponentIngestBatchable`/`OI_ScanRelationshipIngestBatchable`) rather than
inside each Scanner, since the chunking bottleneck is the Mutation Generator/Graph
Repository's per-key commit cost (MetadataScanner.md §0.1 item 4), not the Scanner's own
`scan()` call. Top-level orchestration between types remains Queueable chaining,
unchanged — this ADR's core Decision stands. Batch Apex `execute()`/`finish()`
invocations are not tracked by the Queueable chain-depth counter, so a type of any
real-world size no longer consumes the inter-type chain's depth budget; the chain's
length is once again bounded by the number of configured types, exactly this ADR's
original invariant. See MetadataScanner.md §0.3 for the full amendment detail.

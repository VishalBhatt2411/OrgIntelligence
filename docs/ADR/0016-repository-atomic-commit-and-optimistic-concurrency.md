# ADR-0016: Atomic Version Commit and Optimistic Concurrency in GraphRepository

## Status
Accepted — elaborates [ADR-0012](0012-graph-repository-storage-gateway.md), [ADR-0014](0014-immutable-node-edge-versioning.md)

## Context
[ADR-0012](0012-graph-repository-storage-gateway.md) established `OI_GraphRepository` as the sole storage gateway and sketched its contract as five operations, including two separate calls — `insertVersion` and `flipCurrent` — for what happens when a node/edge gains a new version. Designing this layer at full depth ([GraphRepository.md §0](../GraphRepository.md#0-relationship-to-prior-documents--what-this-corrects-and-adds), §6) surfaced that this was a real defect, not just an incomplete description: calling the two as separate steps leaves a window in which a failure between them results in either zero or two `Is_Current__c = true` rows for the same logical key — both silently wrong, and both violating an invariant ([ADR-0014](0014-immutable-node-edge-versioning.md)) every read path in the platform assumes holds. Separately, Architecture.md §17 already commits the platform to horizontal scan parallelization (independent metadata types scanning concurrently via separate Queueable chains), which makes a second, previously unaddressed problem real: two concurrent transactions could legitimately attempt to version the same key at close to the same instant, and nothing in the design as it stood said what should happen.

## Decision
Two related decisions, both scoped to `OI_GraphRepository`:

1. **`insertVersion` and `flipCurrent` are merged into one atomic operation, `commitVersion`**, never exposed as separately callable steps. It performs the insert and the supersede-flip within a single `Savepoint`-guarded transaction: if either half fails, the other is rolled back, so a caller only ever observes "fully committed" or "cleanly failed," never a partial state.
2. **Concurrent writes to the same key are resolved optimistically, via the deterministic `Node_Version_Key__c`/`Edge_Version_Key__c` (`hash(key + versionNumber)`) External ID's own uniqueness constraint** — not via `SELECT ... FOR UPDATE` pessimistic locking, which does not provide cross-transaction mutual exclusion on Salesforce (a row lock is held only for the duration of the transaction that acquired it, and two concurrent Queueable executions are two separate transactions). When two transactions race to insert the same computed version key, the platform's own uniqueness enforcement causes the second to fail with `DUPLICATE_VALUE`; `OI_GraphRepository` catches this specific failure mode and re-throws a dedicated `OI_ConcurrencyException`, which `OI_GraphBuilder` catches, re-reads current state, and retries its version decision exactly once before surfacing a task-level failure.

## Consequences
- **Positive**: the zero-current/two-current corruption window is closed structurally — there is no code path that can invoke half of `commitVersion`.
- **Positive**: concurrency correctness is achieved without any locking overhead in the common (no-contention) case — the cost of this design is paid only when a genuine race actually occurs, which is expected to be rare given that most nodes are touched by exactly one scanner type.
- **Positive**: the same `DUPLICATE_VALUE`-detection path that resolves concurrency conflicts also resolves replay/retry idempotency for free ([GraphRepository.md §16](../GraphRepository.md#16-idempotency)) — a retried Queueable hop re-attempting an already-committed insert is indistinguishable, at the detection layer, from a genuine concurrent writer, and the same re-read-and-reconcile logic handles both correctly.
- **Negative**: `commitVersion` cannot be bulk-committed across multiple *different* keys in a single call the way a plain insert could — each key's insert-then-flip pair needs its own transactional unit, which is a real, accepted throughput cost at high per-scan change volume ([GraphRepository.md §11](../GraphRepository.md#11-bulk-operations), §24).
- **Negative**: `OI_GraphBuilder` now needs explicit retry-handling logic for a new exception type it previously had no reason to expect — a small but real increase in that class's error-handling surface, mitigated by capping retries at one attempt and treating a second conflict as a genuine task failure rather than retrying indefinitely.

## Alternatives Considered
- **Leave `insertVersion`/`flipCurrent` as two calls, document the ordering requirement, and trust callers** — rejected: this is exactly the defect being corrected; documentation cannot substitute for structural prevention of a partial-write state.
- **A database-level trigger enforcing "at most one current row per key" as a backstop** — rejected as redundant defense-in-depth that would need to run on every DML against these objects, including the archival job's own writes, adding complexity to a path deliberately kept simple.
- **Pessimistic locking (`FOR UPDATE`)** — rejected: does not provide the cross-transaction guarantee needed, since concurrent Queueable chains execute in separate transactions ([GraphRepository.md §15](../GraphRepository.md#15-concurrency-handling)).
- **A dedicated "lock" custom object row per key, acquired and released explicitly** — rejected: reinvents a coordination mechanism the platform's own External ID uniqueness constraint already provides for free, and introduces a new failure mode (a stale lock row surviving a transaction that died mid-way, requiring its own timeout/reap logic).

## Related
[GraphRepository.md](../GraphRepository.md) §0, §6, §14, §15, §16, §21 (Risks), §23 (Alternatives Considered); ADR-0012; ADR-0014; Architecture.md §17.

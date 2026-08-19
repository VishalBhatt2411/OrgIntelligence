# ADR-0013: GraphEngine Facade — Single Public Entry Point

## Status
Accepted — elaborates [ADR-0003](0003-layered-architecture-with-dependency-inversion.md)

## Context
ADR-0003 established strict layering with Services depending on Selector/Repository/Adapter interfaces, reviewed at PR time. As the Graph Engine grew internal structure — a Builder, a Traversal engine, a Repository ([ADR-0012](0012-graph-repository-storage-gateway.md)), a Serializer, and a Cache — the same coupling risk ADR-0003 addresses at the service level reappeared *inside* what had informally been called `OI_GraphService`: nothing stopped `OI_DependencyEngineService` or a Controller from reaching directly into `OI_GraphTraversal` or `OI_GraphRepository` once those existed as named classes, which would silently erode the boundary ADR-0003 already argues for, one convenience-call at a time.

## Decision
Introduce `OI_GraphEngine` as a facade and the *only* public entry point for anything graph-related. External modules — `OI_GraphController`, `OI_DependencyController`, `OI_DependencyEngineService`, `OI_SearchService`, `OI_MetadataScanService` — call `OI_GraphEngine` exclusively. They never call `OI_GraphBuilder`, `OI_GraphTraversal`, `OI_GraphRepository`, `OI_GraphSerializer`, or `OI_GraphCache` directly. The facade's own methods are thin pass-throughs: each routes to exactly one (occasionally two, e.g. cache-then-traversal on a miss) sub-component and returns its result, with **no business logic living in the facade itself** ([GraphEngine.md](../GraphEngine.md) §1.1).

## Consequences
- **Positive**: any of the five internal components can be changed, re-implemented, or replaced (a new traversal algorithm, a new storage provider, a different cache policy) without touching a single caller — the facade's public method signatures are the only contract that matters to the outside.
- **Positive**: this is a direct, one-level-deeper application of ADR-0003's existing service-boundary rule ("a service may call another service's public API; it may never call another service's Selector/Repository/Adapter directly") — the Graph Engine's internals get the same protection its external service boundary already had.
- **Positive**: it gives code review a single, simple check: does this new code reference `OI_GraphBuilder`/`OI_GraphTraversal`/`OI_GraphRepository`/`OI_GraphSerializer`/`OI_GraphCache` from outside the `OI_GraphEngine` class itself? If yes, it's a violation, full stop — much easier to enforce than "be disciplined about which methods you call."
- **Negative**: a facade that accumulates its own logic over time stops being a facade and becomes a second god-object sitting in front of the first one — this is flagged explicitly as a risk ([GraphEngine.md](../GraphEngine.md) §21), with the "zero business logic in the facade" rule as the guardrail, not a one-time guarantee.
- **Negative**: every call now goes through one additional indirection layer versus calling an internal component directly — negligible in Apex, but worth naming rather than ignoring (GraphEngine.md §22).

## Alternatives Considered
- **Status quo — a single `OI_GraphService` doing build/expand/filter itself, informally** — rejected: this was the design being corrected; it doesn't scale to five distinct internal responsibilities without becoming a monolith itself.
- **No facade; rely on convention/documentation to discourage calling internals directly** — rejected: convention without enforcement erodes over time, especially across a team or across AI-assisted contributions that don't have the full history of *why* a boundary exists; a single class that's the only thing importable/callable from outside is a structural guarantee, not a hope.
- **Expose each of the five internal components as its own public service, coordinated by callers** — rejected: this just moves the coordination logic (and the coupling) into every caller instead of centralizing it once; it also makes swapping an internal component's implementation a multi-caller change instead of a single-class change.

- **Positive, extended beyond Apex**: [GraphUI.md](../GraphUI.md) §3 applies the identical "only one entry point, everything else is internal" reasoning one layer further out, at the LWC boundary — `oiGraphCanvas` and its rendered children never call Apex at all, only container components do, the UI-layer parallel to this ADR's own facade rule.

## Related
[GraphEngine.md](../GraphEngine.md) §1.1, §7, §7.1, §21; ADR-0003; ADR-0012; Architecture.md §4; [GraphUI.md](../GraphUI.md) §3, §30.

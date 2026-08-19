# ADR-0020: SVG-Based Rendering with a Narrowly-Vendored Layout Library, Not Canvas/WebGL

## Status
Accepted

## Context
The Visual Graph Canvas needs a concrete rendering technology decision this platform had not yet made. Requirements: rich per-node interactivity and keyboard/screen-reader accessibility (`CLAUDE.md` §UI Philosophy's explicit keyboard-navigation commitment; CodingStandards §10's existing ARIA rule); no CDN-loaded scripts and full CSP compliance (`CLAUDE.md` §Technical Stack; CodingStandards §11); the platform's own structural guarantee that it never loads an unbounded graph (every fetch is hop-depth- and node-count-bounded, [GraphEngine.md §12](../GraphEngine.md#12-graph-traversal-algorithms)), meaning raw rendering throughput at massive element counts is not a real constraint here the way it would be for an unbounded-data visualization tool.

## Decision
Render nodes and edges as SVG — real DOM elements, virtualized so only in-viewport-plus-margin elements exist in the DOM at any time ([GraphUI.md §4](../GraphUI.md#4-graph-canvas-architecture), §26). Do not use Canvas 2D or WebGL. A single, narrowly-scoped vendored library supplies force/radial layout position math only ([GraphUI.md §17](../GraphUI.md#17-layout-strategy), [ADR-0019](0019-hybrid-radial-graph-visualization.md)) — it is not given ownership of rendering, data-binding, or interaction, all of which this platform's own architecture (the container/presentational component split, the reference-counting visibility model, the Presentation Type Registry) already specifically solves. Nodes are individually componentized (`oiGraphNode`, one LWC instance per rendered node); edges are not — they are drawn directly by the Canvas as SVG paths in a single pass, with interaction handled via event delegation rather than per-edge component instances ([GraphUI.md §5, §6](../GraphUI.md#5-node-component-architecture)).

## Consequences
- **Positive**: real DOM elements per node give native focusability, tab order, ARIA labeling, and CSS/SLDS-token-based styling (including dark mode) essentially for free — a Canvas/WebGL bitmap surface would require hand-building a synthetic accessibility tree and a custom hit-testing layer to reach the same baseline this decision gets natively.
- **Positive**: because the platform structurally never loads an unbounded graph, SVG's higher per-element cost relative to a bitmap surface never actually materializes as a real-world performance problem at this platform's own stated scale — the concern that usually motivates choosing Canvas/WebGL over SVG does not apply here.
- **Positive**: scoping the vendored dependency to layout math only, rather than adopting a full graph-visualization framework, keeps the third-party surface small and auditable (CodingStandards §11's CSP/license review) and avoids a framework fighting this platform's own already-designed rendering/state architecture for control it doesn't need.
- **Negative**: at a hypothetical future scale far beyond this platform's current bounded-fetch ceilings, SVG's real-DOM-per-element cost would eventually become a genuine constraint — not a concern for v1 given the structural bounds already in place, but named honestly as the condition under which this decision would need revisiting.
- **Negative**: edges being Canvas-owned SVG paths rather than components means edge-specific interactivity (beyond hover-highlight and click-for-detail) requires new Canvas-level event-delegation logic rather than simply extending a component's own contract — an accepted asymmetry, justified by edge volume being typically much higher than node volume for the same fragment.

## Alternatives Considered
- **Canvas 2D** — rejected: forfeits native accessibility and hit-testing for a raw-throughput benefit this platform's own bounded-scale guarantees make unnecessary.
- **WebGL** — rejected: same reasoning as Canvas 2D, with substantially more implementation complexity for accessibility and interaction than the benefit justifies at this platform's actual scale.
- **A full, opinionated third-party graph-visualization framework** (owning rendering, layout, *and* interaction) — rejected: would duplicate or conflict with architecture this document already specifically designed (the container/presentational split, the reference-counting model, registry-driven styling), and would widen the vendored-dependency surface subject to CSP/license review well beyond what the actual need (layout math) requires.
- **Componentizing edges the same way as nodes** — rejected: real, avoidable per-instance overhead at typically-higher edge volume, for interactivity the interaction model doesn't need per edge instance ([GraphUI.md §6](../GraphUI.md#6-edge-component-architecture)).

## Amendment (2026-08-19): the layout-math library was implemented in-house, not vendored

This decision's SVG-vs-Canvas/WebGL reasoning (the Decision/Consequences above) stands unchanged. But the "narrowly-vendored library supplies force/radial layout position math" clause never happened, and — having now actually built that math (`oiGraphCanvas.js`'s `computeBaseLayout`, a barycenter-reordering relaxation over fixed-radius rings) — should not be revived as written:

- The concrete algorithm this canvas needs (fixed-radius concentric rings, arc-slicing for guaranteed same-ring non-overlap, circular-mean angular attraction restricted to strictly-inner rings for convergence) has no drop-in off-the-shelf equivalent. A general force-simulation library (d3-force and similar) assumes free 2D positions, not a fixed-radius/ring-constrained layout — adopting one would mean overriding most of its own position-update logic anyway, while still taking on the static-resource pinning/licensing/CSP audit this ADR's own Consequences section named as a cost (CodingStandards §11).
- The in-house implementation is small (~100 lines of pure, dependency-free functions), fully auditable as first-party code, and already covered by a dedicated Jest test (`oiGraphCanvas.test.js`, the hub multi-parent case) — the same accessibility/interactivity/CSP benefits this ADR already argued for SVG-over-Canvas apply doubly to keeping the layout math in-house rather than adding a third-party surface for a genuinely bespoke problem.
- **Revised decision**: no vendored layout-math library is planned. If a future need genuinely exceeds what an in-house radial/barycenter approach can do (e.g., a fundamentally different, unconstrained force-directed mode), that would warrant a new ADR evaluating vendoring at that time, not a revival of this clause.

## Related
[GraphUI.md](../GraphUI.md) §4, §5, §6, §17, §25, §28, §32, §36, §39–§40; ADR-0019; CodingStandards.md §10, §11.

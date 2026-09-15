# ADR-0026: Org Health Dashboard — Visual Contract and Compute-Tier Architecture

## Status

Accepted

## Context

`ProductSpecs.md` Phase 4 (Org Health) specifies a seven-section dashboard (Org Overview, Metadata Health, Automation Health, Code Health, Security Health, Data Health, Storage) with two rules in tension: prefer deriving insights from the current graph, scan metadata, and bounded live queries rather than adding persistent analytics objects, while never running unbounded full-org profiling synchronously. Left unresolved, this ambiguity risks either a proliferation of ad hoc persisted caches (violating the first rule) or a page that silently times out on large orgs (violating the second).

Separately, the user has been explicit that prior UI work in this repository has repeatedly fallen short of the intended visual bar, and asked for this surface specifically to be built to a materially higher standard. `docs/CurrentUIVisualGapAssessment.md` already documents the concrete failure modes (undesigned empty states, default-accordion density, inconsistent iconography, wasted canvas) that occurred without a binding visual contract, and ADR-0025 established the fix for Object Analyze mode: a product-owner-approved reference image plus a mandatory screenshot-diff acceptance process, not prose description alone.

## Decision

**Compute-tier architecture.** Each Org Health metric is assigned to exactly one of three tiers, not a single uniform pattern:

- **Tier 1 (live, unpersisted)** — Org Overview, Storage. Cheap enough to compute on every request.
- **Tier 2 (live, bounded)** — most Metadata/Automation/Code/Security Health metrics. Bounded aggregate SOQL with a configurable row ceiling and an honest `coverageNote`/`truncated` flag when the ceiling is hit.
- **Tier 3 (async, persisted)** — Data Health unconditionally (named explicitly by the spec's "never unbounded... synchronously" rule), plus the small number of individual metrics that require enumerating every current node of a type rather than an aggregate (Metadata Health's orphan/unused-field detection, Code Health's stale-API-version audit). These write to one new object, `OI_Org_Health_Snapshot__c`, kept deliberately minimal in scope rather than becoming a general-purpose analytics table.

No composite "Org Health Score" rolling up all seven sections ships in v1 — each section's score (where the spec asks for one) is independently formula-backed; a meta-score would itself need a formula-of-formulas to stay honest, and is deferred rather than invented under time pressure.

**Visual contract.** Adopt `OrgHealthVisualDesignSpecification.md` as the binding visual contract for the Org Health tab, extending — not replacing — `VisualDesignSpecification.md`'s existing token system, mirroring ADR-0025's decision structure. Pixel-level acceptance applies to two representative views (the Overview landing grid and the Metadata Health detail view); the remaining five sections and all loading/empty/error states are governed by the shared token and component contract plus Jest fixture coverage, not individual reference captures — proportionate rigor given the number of states involved.

**Severity governance.** A new `OI_Health_Severity_Descriptor__mdt` extends the existing Node/Edge Type Descriptor registry pattern (`GraphUI.md` §20–21) rather than letting each section invent its own red/amber/green logic. Score/severity color is a separate channel from the application's blue accent color; the accent never signals status and severity tokens are never used for interactive elements.

## Consequences

- A vertical slice (Storage + Org Overview, both Tier 1) can ship and be visually accepted before any async/persisted-tier work exists, giving an early, real end-to-end validation of both the compute-tier split and the visual contract.
- `OI_Org_Health_Snapshot__c` stays justified and small rather than becoming a dumping ground — if a future metric is tempted onto Tier 3, that is a deliberate architectural decision to revisit against this ADR, not a default.
- Visual fidelity for the two named views becomes objectively reviewable instead of a subjective "polish" task; the other five sections inherit the same tokens/components by construction rather than by individual review.
- A future org-wide composite score, if ever built, must itself expose a formula (which sections, which weights) rather than being presented as a single opaque number — this ADR does not authorize skipping that.

## Related

`ProductSpecs.md` Phase 4; `OrgHealthVisualDesignSpecification.md`; `VisualDesignSpecification.md`; ADR-0025; `GraphUI.md` §20–21, §29; `docs/CurrentUIVisualGapAssessment.md`.

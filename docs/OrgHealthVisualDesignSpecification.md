# Org Health — Reference Visual Specification

Status: Approved visual target — §4, §5, and §7 amended by [ADR-0028](ADR/0028-unified-cross-surface-design-token-system.md)

Owner: Product + UX Architecture

Amendment note (2026-09-02): a cross-surface audit found that this document's §4 claim of verbatim
token reuse and its §7 claim of an identical breakpoint ladder were both inaccurate, and that its
§5 rem type scale prescribes sizes outside the 12–14 px band §4 restates. Separately, the severity
token audit this document's own §4 required has now been run against `projectOrg` and **falsified
the severity mapping below** — see §4. `--oi-*` token names and values now live in ADR-0028 §5, and
where this document and ADR-0028 differ on a value, ADR-0028 controls. Everything else here —
anatomy, card and score-ring contracts, the five-state contract, acceptance scope — remains binding.

Applies to: the Org Health tab in the Salesforce Org Intelligence Platform, API v67.0

Reference artifact: the "Org Health" mockup Artifact reviewed and approved by the product owner on 2026-08-31 (three views: Overview landing grid, Metadata Health detail, shared component kit). Scope note, per this document's own §1: pixel-fidelity acceptance applies to the **Overview landing grid** and the **Metadata Health detail view** only; the remaining five sections and every loading/empty/error state are governed by the token and component contract in §4–§6, not by their own individual reference captures — proportionate to `docs/ADR/0025-reference-image-as-binding-visual-acceptance-contract.md`'s precedent without requiring a separate mockup per section.

## 1. Authority and interpretation

This document is the binding visual acceptance contract for the Org Health tab, mirroring ADR-0025's role for Object Analyze mode. For this surface, it is more specific than the general UI guidance in `ProductSpecs.md`, `GraphUI.md`, `Architecture.md`, and `CodingStandards.md`. Those documents still govern data, security, packaging, component boundaries, and performance.

This spec deliberately **extends** `VisualDesignSpecification.md`'s token system (§4 below reuses its color/radius/shadow values) rather than defining a competing one — Org Health should visually read as the same product as Object Analyze mode, not a second design language bolted on.

The following are not acceptable substitutes for matching the reference:

- merely using SLDS components;
- a technically correct dashboard with materially different density, hierarchy, or card treatment;
- default `lightning-accordion`/table styling standing in for the designed category-card and disclosure patterns below;
- declaring success from Jest tests or source inspection without screenshot comparison, for the two pixel-bound views named above.

## 2. Ownership boundary

Same two zones as `VisualDesignSpecification.md` §2: Salesforce-owned global shell (out of scope, cannot be pixel-controlled by a packaged LWC) and the application-owned workspace (the Org Health tab content), which pixel-fidelity rules apply to.

## 3. Reference anatomy

### 3.1 Section nav

- A left-aligned, horizontally scrollable custom tab strip (`role="tablist"`, not `lightning-tabset` — matches `oiGraphExplorer`'s existing mode-switch precedent), one entry per section (Overview, Metadata Health, Automation Health, Code Health, Security Health, Data Health, Storage), each carrying a small severity dot.
- Sits directly below the page header, above a thin bottom border; the active tab is marked by an underline in the accent color, not a filled background.

### 3.2 Overview landing grid

- A full-width KPI hero strip (Objects, Fields, Apex Classes, Triggers, Flows, Permission Sets, Dependencies, Relationships) rendered as compact white tiles in a single responsive row: 8-up ≥ 1280px, 4-up 768–1279px, 2-up below 768px.
- Below it, a responsive grid of 6 category summary cards (Metadata, Automation, Code, Security, Data, Storage) — 3-up ≥ 1280px, 2-up 1024–1279px, 1-up below 1024px.
- Each category card: a colored square icon tile top-left, category title and subtitle, a score ring **or** a "Facts only" badge (never both, never an invented score where the spec forbids one) top-right, 2–3 top KPI rows, and a footer pairing a severity badge with a "View details" affordance.

### 3.3 Detail view (Metadata Health is the pixel-bound exemplar)

- A back-to-overview affordance, then a header card: large score ring, section title, an expandable formula disclosure directly beneath the header (open by default on first visit), a coverage pill top-right ("N / M objects scanned") and a "computed at" timestamp.
- A 4-tile KPI row.
- A two-column split at 1024px and above, collapsing to one column below it: a breakdown table (object/field name, metric columns, severity badge per row) on the left, a signal heatmap (object × metric grid, severity-colored cells) on the right.

### 3.4 Shared components (token/pattern-bound, not pixel-bound per section)

Score ring, KPI tile, severity badge, state banner (five distinct states — true zero / coverage incomplete / not yet run / not obtainable / request failed, never collapsed into a generic blank or spinner), formula disclosure, breakdown list, heatmap grid, loading skeleton. Every section built after Metadata Health composes these primitives rather than inventing section-specific styling.

## 4. Visual tokens

Shared with every other surface through the canonical vocabulary in
[ADR-0028](ADR/0028-unified-cross-surface-design-token-system.md) §5 — no competing palette:

| Role                       | Token                                                          |
| -------------------------- | -------------------------------------------------------------- |
| Card/tile surface          | `--oi-color-surface`                                           |
| Page background            | `--oi-color-surface-sunken`                                    |
| Primary text               | `--oi-color-text-primary`                                      |
| Secondary text             | `--oi-color-text-secondary`                                    |
| Muted text                 | `--oi-color-text-muted`                                        |
| Accent (interactive/brand) | `--oi-color-accent`                                            |
| Border                     | `--oi-color-border`                                            |
| Card shadow                | `--oi-shadow-card`                                             |
| Card radius                | `--oi-radius-lg` (8 px)                                        |
| Control radius             | `--oi-radius-md` (6 px)                                        |
| Body type                  | `--oi-font-size-caption` … `--oi-font-size-body-lg` (12–14 px) |

This table previously collapsed `VisualDesignSpecification.md`'s three text roles into one
"Secondary/muted" row offering two hexes without saying which applied where. The three-tier
taxonomy is restored above; it maps onto SLDS's own three `on-surface` tiers.

Severity is a **separate** semantic channel from the accent color above — it is never used for interactive/brand elements, and the accent is never used to signal status:

| Severity                     | Token                                                               |
| ---------------------------- | ------------------------------------------------------------------- |
| Good                         | `--oi-color-severity-good`                                          |
| Warning                      | `--oi-color-severity-warning`                                       |
| Critical                     | `--oi-color-severity-critical`                                      |
| Not scanned / not obtainable | `--oi-color-severity-none` — never colored as if it were a severity |

**The audit this section required has been run, and it falsified this document's original
mapping.** Probing computed styles on the deployed Org Health page in `projectOrg` on 2026-09-02
established that the SLDS severity families do not carry traffic-light semantics in this org:
`--slds-g-color-success-1` resolves to `#056764` (dark teal, not green),
`--slds-g-color-warning-1` and `--slds-g-color-warning-base-40` to `#8c4b02` (brown, not amber),
and `--slds-g-color-error-1` and `--slds-g-color-error-base-40` to `#b60554` (magenta, not red).
The teal additionally collides with `--oi-color-rel-master-detail` (`#0b827c`) on the graph canvas.
Binding severity to those families would therefore destroy the status semantic — exactly the
collision this section anticipated. Per ADR-0028 §2, severity is consequently the platform's second
justified hardcoded exception: literal, guaranteed-distinct, authored with `light-dark()` so it
still follows a future dark theme, and overridable by a consuming org. The `oiHealth*` components'
existing hardcoded severity hexes were correct and are preserved as the token values.

Note also that the original mapping named two different SLDS token shapes (`success-1` and
`error-1` against `warning-base-40`); both warning forms were probed and resolve identically here,
so nothing turned on the discrepancy.

## 5. Card and score-ring contract

- Category summary card: icon tile (`--oi-icon-tile`, `--oi-radius-lg`), title `--oi-font-weight-bold` at `--oi-font-size-title`, subtitle `--oi-color-text-muted` at `--oi-font-size-caption`, ring or facts badge top-right, 2–3 KPI rows at `--oi-font-size-body` with `--oi-font-numeric` values, footer severity badge + view-details link.

  These replace the original `~2.1rem / ~0.95rem / ~0.72rem / ~0.78rem` values. At this org's
  measured 16 px root, `0.95rem` (15.2 px) and `0.72rem` (11.5 px) fell outside the 12–14 px body
  band restated in §4, so the two clauses could not both be satisfied; the icon tile at 2.1rem
  (33.6 px) likewise exceeded `VisualDesignSpecification.md` §5's stated 30–32 px. ADR-0028 §4
  resolves this by binding the band to body text and making headings and uppercase micro-labels
  named steps on one shared scale.

- Score ring: SVG stroke-based, severity-colored value stroke over a neutral track, centered numeral in a monospace/tabular-figure treatment so scores read as computed data, not decoration. A "not scanned" ring renders as a dashed, muted track with no numeral — never a colored ring implying a real score.
- Formula disclosure: every scored section's DTO carries a `formula` string consumed by this one shared component — this is the structural mechanism, not a per-section convention, that keeps "any score must expose formula" true by construction.

## 6. Loading / empty / error state contract

Five distinct states, enforced by one shared state-banner component across every section — collapsing any two of these into a generic blank/spinner/toast is a defect, not a simplification:

1. **True zero** — a real, confirmatory finding (e.g. "0 orphaned objects"). Quiet, non-alarming styling.
2. **Coverage incomplete** — unscanned/stale/partial data. Distinct banner with a last-scan timestamp and a link to scan status; the score ring itself renders visually provisional (dashed/muted), never presented with the same confidence as a fully-covered score.
3. **Not yet run / queued / running** — Data Health only, reusing `OI_Scan_Run__c.Status__c`'s vocabulary.
4. **Not obtainable** — a structural fact (e.g. a metric the org's API doesn't expose). Styled as permanent, never as a retryable error.
5. **Request failed** — sanitized message + correlation id, retry scoped to just that section; a landing-grid fetch failure in one section's card must not blank the other six.

## 7. Responsive behavior

The single platform ladder defined in [ADR-0028](ADR/0028-unified-cross-surface-design-token-system.md)
§6, identical to `VisualDesignSpecification.md` §7's: **1280 / 1024 / 768**. At ≥1280px full
multi-column layout; at 1024–1279px narrower grids and gaps with the category grid at 2-up; at
768–1023px the category grid drops to 1 column and the detail split stacks; below 768px functional
but not pixel-identical. No breakpoint may cause cards, rings, or badges to overlap or clip.

This section previously asserted an identical ladder while §3 introduced 620px, 640px, and 980px
lines that `VisualDesignSpecification.md` does not have, and the two sections disagreed at
768–1023px (§3.2 prescribed 2-up, this section permitted 1-up). The extra lines are deleted and the
grid counts in §3.2 and §3.3 are restated on the shared ladder, resolving the contradiction in
favor of 1-up.

The acceptance viewport is **1536 × 1024 at 100% zoom**, inherited explicitly from
`VisualDesignSpecification.md` §9 rather than left implicit as it was before.

## 8. Acceptance process

Identical procedure to `VisualDesignSpecification.md` §9 (same-viewport real-org screenshot, crop Salesforce chrome, overlay/perceptual diff, region-by-region mismatch log, product-owner sign-off), applied to exactly two states: the Overview landing grid, and the Metadata Health detail view. The other five sections and every loading/empty/error state are accepted against §4–§6's token/pattern contract plus their own Jest fixture coverage — not a separate screenshot diff each.

Automated component tests validate behavior but cannot approve visual fidelity for the two pixel-bound views. A written claim such as "matches the design" without a captured comparison is not acceptance evidence for those two views.

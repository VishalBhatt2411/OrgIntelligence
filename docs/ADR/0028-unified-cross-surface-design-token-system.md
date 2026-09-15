# ADR-0028: Unified Cross-Surface Design Token System

## Status

Accepted — reconciles 0025 and 0026

## Context

The platform ships three application surfaces — Graph Explorer, Hierarchy Manager, and Org Health —
built at different times against different specifications. An evidence-based audit of all 35 LWC
stylesheets and the two binding visual specifications established the following, none of it
speculative:

**There is no shared visual layer.** Zero shared CSS files, zero static resources, zero `:host`
blocks. `--oi-*` custom properties are defined in only four components, each private to its own
shadow root, and `--oi-node-accent` is defined **twice with conflicting values**
(`oiGraphNode.css:10` resolves it from `--slds-g-color-border-2`, `oiSchemaObjectCard.css:8` from
`--slds-g-color-accent-1`). `VisualDesignSpecification.md` §4 mandates centralizing tokens as CSS
custom properties "at the application shell" and forbids "arbitrary per-component substitutes";
that mandate has never been implementable because **no document defines a single `--oi-*`
identifier**.

**The drift is two coherent palettes, not noise.** 53 distinct hex values across 570 occurrences,
26 distinct font sizes (17 inside the 0.58–0.9rem band alone), 15 border-radii, 15 box-shadows, and
`--slds-g-shadow-2` given eight different fallback values depending on which file reads it. Six
semantic roles carry two competing values each:

| Role        | `oiHealth*` family    | `oiGraph*` / `oiHierarchy*` family |
| ----------- | --------------------- | ---------------------------------- |
| Brand       | `#0b5cff`             | `#0176d3`                          |
| Body text   | `#12161f`             | `#181818`                          |
| Muted text  | `#8892a0`             | `#706e6b`                          |
| Border      | `#edf0f4` / `#e2e7ee` | `#e2e1df` / `#dddbda`              |
| Success     | `#2e844a`             | `#04844b`                          |
| Error       | `#ba0517`             | `#c23934`                          |
| Shadow tint | `rgba(15,23,42,…)`    | `rgba(0,0,0,…)`                    |

`oiHealthFindingDrawer` and `oiHealthRemediation` already mix both families, so the seam is
actively leaking rather than holding at a surface boundary.

**The two specifications contradict each other.** `OrgHealthVisualDesignSpecification.md`:53 claims
its palette is "[r]eused verbatim" from `VisualDesignSpecification.md` §4 and :97 claims the "[s]ame
breakpoint philosophy". Neither claim survives reading. The material divergences are enumerated and
resolved in §Decision below.

**A live token audit in `projectOrg` (2026-09-02) overturned a spec assumption.**
`OrgHealthVisualDesignSpecification.md`:77 required auditing severity tokens against the org's real
rendered theme before fixing fallbacks. That audit has now been run by probing computed styles on
the deployed Org Health page. SLDS 2 tokens are present and authored with CSS `light-dark()`, root
font size is **16px**, and:

- `--slds-g-color-success-1` resolves to `#056764` — a dark **teal**, not green
- `--slds-g-color-warning-1` and `--slds-g-color-warning-base-40` resolve to `#8c4b02` — **brown**
- `--slds-g-color-error-1` and `--slds-g-color-error-base-40` resolve to `#b60554` — **magenta**

So the severity mapping that `OrgHealthVisualDesignSpecification.md` §4 mandates does not deliver
traffic-light semantics in this org. Bound naively, Good/Warning/Critical read teal/brown/magenta,
and the teal collides with the master-detail relationship color `#0b827c` used on the graph canvas.
The `oiHealth*` components' hardcoded `#2e844a`/`#b95000`/`#ba0517` were therefore **correct**, not
careless — they were an undocumented workaround for a real defect.

The audit also confirmed `--slds-g-color-accent-1`, `--slds-g-color-border-accent-1`, and
`--slds-g-color-accent-container-1` are all `#066afe` in this org (the collision already recorded
for the accent pair), that `--slds-g-color-accent-4` is not declared at all so its fallback always
wins, and that `--slds-g-color-accent-2`/`-3` resolve to `#0250d9`/`#022ac0` — reproducing exactly
the near-identical blues documented in `oiRelationshipCanvas.css`:6–13.

Finally: `color-scheme` computes to `normal` on both `:root` and `body`, so every SLDS
`light-dark()` token currently resolves to its light value — **even on a machine whose OS reports
`prefers-color-scheme: dark`**. Any dark-mode handling keyed to that media query would flip this
application's colors while SLDS's stayed light.

**The absent token layer is already causing live rendering defects, not merely inconsistency.**
Probing the deployed page established that `oiHealthKpiTile` — a 31-line stylesheet — renders three
of them, because the SLDS `on-surface` tiers were consumed with inverted assumptions about which
tier is strongest:

- its uppercase eyebrow label resolves to `#03234d` (dark navy) while the KPI value it labels
  resolves to `#5c5c5c` (mid grey), so **the label is visually stronger than the number** — the
  intended hierarchy, per the literal fallbacks the same rules carry, was the exact reverse;
- its card border resolves to `#5c5c5c` rather than the intended near-white `#edf0f4`, because
  `--slds-g-color-border-2` is the _strong_ border token in SLDS 2, not the subtle one;
- and its declared typeface never loads (below).

`--slds-g-color-on-surface-1` is the weakest tier (`#5c5c5c`) and `-3` the strongest (`#03234d`);
several components assume the opposite. The token mapping in §5 fixes this class of defect by
construction, since a component asks for `--oi-color-text-primary` rather than picking an SLDS tier
and guessing.

**Identity was bound to severity, producing misleading UI.** The Org Health landing grid's six
category monograms took their color from the _severity_ palette as a fixed property of each
section, regardless of that section's actual score. Data Health's tile was severity-amber while the
section scored 95 and carried a Good badge inches away; Code Health's was severity-green whatever
its score happened to be. A monogram that encodes a status it does not measure is misleading
whenever the two disagree, and nothing prevented them from disagreeing. This is what forces a
fourth color channel (categorical identity) rather than a looser reading of channel separation.

**Three declared webfonts have never rendered.** 18 components declare `'Manrope'`,
`'IBM Plex Sans'`, or `'IBM Plex Mono'` across 37 rules. The package contains no static resources,
the rendered document carries exactly one `@font-face` rule (Salesforce's icon font), and all three
families measure byte-identical to the platform fallback. Both specifications mandate
"Salesforce Sans/system sans-serif", so the specification-compliant resolution is to drop the
webfonts rather than package them — packaging would add weight and a Security Review surface to
reach an appearance no binding document asks for. Three competing monospace stacks collapse to one
at the same time.

## Decision

### 1. One token module, consumed by every component

A CSS-only LWC module `c/oiDesignTokens` defines the complete token vocabulary on `:host` and is
consumed with `@import 'c/oiDesignTokens';` at the top of every component stylesheet. This is the
native platform mechanism for sharing CSS style rules, requires no static resource, and is fully
package-compatible.

Tokens are declared on `:host` rather than relying on inheritance from an ancestor, so a component
carries its own token scope and renders correctly wherever App Builder places it — the three
surfaces are separate FlexiPages with sibling root components, so there is no common ancestor to
inherit from.

No component may introduce a private colour, font size, radius, shadow, or spacing literal. A
component-scoped custom property remains permitted for values that are genuinely local geometry
(e.g. `oiHierarchyTreeNode`'s JS-driven `--oi-tree-indent`), and for a per-node accent injected
from JS, which must resolve _from_ a token.

#### Shared pattern modules built on top of it

The same CSS-only mechanism carries two _pattern_ vocabularies, each importing
`c/oiDesignTokens` itself:

| Module               | Vocabulary                                                                      | Replaces                                                                                                         |
| -------------------- | ------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `c/oiComboboxStyles` | `.oi-combobox*` — a search input with a suggestion panel                        | two divergent private copies in `oiSearchBar` and `oiRecordPicker` (which stay separate components per ADR-0017) |
| `c/oiButtonStyles`   | `.oi-btn`, `.oi-btn_primary`, `.oi-btn_link` — the native `<button>` vocabulary | `.oi-health-btn`, copy-pasted into eight stylesheets                                                             |

The button module is the clearest argument for this pattern. The eight `.oi-health-btn` copies had
drifted: three carried **no `:focus-visible` rule at all**, so their buttons showed no focus
indicator — an accessibility defect `VisualDesignSpecification.md` §8 forbids, and one detectable
only by diffing the copies against one another. Three others omitted `font-family`/`line-height`,
so the same button rendered at a different size depending on which section it appeared in, and the
`-primary` variant existed in only two. A single definition makes that class of drift impossible.

A pattern module carries appearance only, never one consumer's layout. `c/oiButtonStyles`
deliberately omits `align-self`: setting it would fix a full-width Save button inside a flex-column
form in one line, but the same declaration drags a button off centre in a flex-row page header.
Column geometry belongs to the component that owns the column.

These modules style **native** elements. `lightning-button` and `lightning-icon` render into closed
Salesforce shadow roots that no stylesheet here can reach, so components using them are outside
this vocabulary by construction, not by omission.

Any new CSS-only module must also be added to `jest.config.js`'s `moduleNameMapper` alternation, or
every consuming component's test suite fails to resolve the import.

### 2. SLDS-first with literal fallbacks, and exactly three documented exceptions

Every token resolves as `var(--slds-g-color-…, <literal>)` so the application inherits customer org
theming and future dark mode, degrading to the specification's literal where SLDS 2 tokens are
absent. This promotes the convention already documented in `oiRelationshipCanvas.css`:1–14 from one
component's local practice to a platform rule.

Three exceptions are permitted, each justified by measured evidence, each hardcoded and each still
overridable by a consuming org:

1. **Relationship-kind colors** — the existing exception. `--slds-g-color-accent-2`/`-3` are
   visually indistinguishable in this org, which defeats the legend's entire purpose.
2. **Severity colors** — the new exception established by this ADR. The SLDS severity families do
   not render as green/amber/red in this org (see Context), so binding to them destroys the
   status semantic and collides with the structural teal.
3. **Elevation** — both specifications fix `0 2px 8px rgba(15, 23, 42, 0.10)` exactly, while the
   org's real `--slds-g-shadow-1`/`-2` are multi-layer shadows with materially different geometry.
   The specification value is binding, so shadows are literal.

### 3. Dark mode uses `light-dark()`, never `prefers-color-scheme`

Tokens needing a dark variant are authored as `light-dark(<light>, <dark>)`, keying off the same
`color-scheme` signal SLDS itself uses. This resolves to the light value today, matching current
rendering exactly, and follows automatically if Salesforce flips `color-scheme`. Using
`@media (prefers-color-scheme: dark)` is **prohibited** in this codebase: it would darken this
application's tokens while every SLDS token stayed light, producing a half-dark UI.

### 4. Conflict resolutions between the two specifications

| #       | Conflict                                                                                                                                | Resolution                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| ------- | --------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| C1      | Org Health prescribes rem type sizes (15.2px title, 11.5px subtitle) outside the 12–14px band it restates one paragraph earlier         | Root font size is declared as **16px**. The 12–14px band binds **body text only**; headings and uppercase micro-labels are explicit, named exceptions on the scale in §5. Both specs are amended to say so.                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| C2      | Icon tile 30–32px vs ~2.1rem (33.6px)                                                                                                   | One token, **2rem (32px)**, inside `VisualDesignSpecification.md`'s stated range.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| C3      | Org Health collapses three text roles into two, leaving which hex applies where undefined                                               | VDS's **three-tier** taxonomy is canonical, and maps cleanly onto SLDS's own three tiers: primary→`on-surface-3`, secondary→`on-surface-2`, muted→`on-surface-1`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| C4, C12 | Same values, renamed roles ("Salesforce action blue" vs "Accent"; "Canvas/surface" vs "Card/tile surface")                              | Token names in §5 are canonical; both specs adopt them. Org Health's channel-separation rule (accent never signals status, severity never used for interaction) is adopted platform-wide.                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| C5, C6  | Severity palette mandated by one spec, absent from the other; its green collides with VDS's reserved structural green `#1f9d61`         | The platform has **four independent color channels** that may never be substituted for one another: accent (interaction/brand), severity (status), structural (relationship kind), and categorical identity ("which thing is this"). Severity tokens appear only inside severity-bearing components (badge, score ring, heatmap cell, state banner); structural tokens only on graph-canvas chrome; identity tokens only on monogram tiles and type accents. Additionally, `VisualDesignSpecification.md`:102's redundant-encoding rule is **extended to severity**: severity is always carried by a text label or glyph as well as color, never by color alone. |
| C7, C8  | Org Health adds 620px and 980px breakpoints absent from VDS, and contradicts itself at 768–1023px (§3.2 says 2-up, §7 says may be 1-up) | **One ladder: 1280 / 1024 / 768.** The 620px and 980px lines are deleted. Grid counts restated in §6 below.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| C9      | VDS fixes a 1536 × 1024 reference viewport; Org Health fixes none while importing VDS's same-viewport, 4px-tolerance procedure          | **1536 × 1024 at 100% zoom** is the acceptance viewport for every surface.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| C10     | VDS mandates uppercase in four places; Org Health is silent, so a section header could ship title-case and violate nothing              | Uppercase is a named type role (`--oi-font-size-micro` + `--oi-letter-spacing-caps`) and applies to lane headings, panel/section labels, and pills on every surface.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| C11     | VDS says "bold", Org Health says 700                                                                                                    | Numeric weights only: **400 / 600 / 700**. The 500 and 800 weights currently in use are retired.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |

### 5. The canonical vocabulary

Names are normative; the literals below are the migration's starting values.

**Color — surface and text**

```
--oi-color-surface           var(--slds-g-color-surface-container-1, #ffffff)
--oi-color-surface-sunken    var(--slds-g-color-surface-container-2, #f7f8fa)
--oi-color-text-primary      var(--slds-g-color-on-surface-3, #17233d)
--oi-color-text-secondary    var(--slds-g-color-on-surface-2, #44506a)
--oi-color-text-muted        var(--slds-g-color-on-surface-1, #6b7280)
--oi-color-border            var(--slds-g-color-border-1, #d9dde5)
--oi-color-border-strong     var(--slds-g-color-border-2, #c9c7c5)
--oi-color-accent            var(--slds-g-color-accent-1, #0b5cff)
--oi-color-accent-strong     var(--slds-g-color-accent-2, #014486)
--oi-color-accent-wash       rgba(11, 92, 255, 0.10)
--oi-color-on-accent         var(--slds-g-color-on-accent-1, #ffffff)
```

**Color — severity** (exception 2: hardcoded, `light-dark`, never bound to SLDS severity families)

```
--oi-color-severity-good          light-dark(#2e844a, #45c65a)
--oi-color-severity-warning       light-dark(#b95000, #f0a020)
--oi-color-severity-critical      light-dark(#ba0517, #fe8aa7)
--oi-color-severity-none          var(--slds-g-color-on-surface-1, #6b7280)
--oi-color-severity-good-wash     light-dark(#e6f4ea, #10321c)
--oi-color-severity-warning-wash  light-dark(#fdf0e4, #3a2100)
--oi-color-severity-critical-wash light-dark(#fceaec, #40060f)
--oi-color-severity-none-wash     light-dark(#eef1f5, #22262c)
```

**Color — categorical identity** (a third channel: "which thing is this", never a status)

```
--oi-color-identity-1 … -7         light-dark() pairs: blue, violet, teal, indigo, plum, slate, cyan
--oi-color-identity-1-wash … -7-wash
```

Deliberately excludes green and red so an identity tile can never read as severity. Permitted only
as a monogram/icon tile fill or a metadata-type accent — never a badge, body text, or score — and
any card using one must still carry its real severity in a labelled badge. The numbering keeps
product taxonomy out of the token layer. This family serves both the Org Health section monograms
and the metadata-type accents previously hardcoded in `oiNodeDetailPanel`.

Migrating that second consumer changed two hues deliberately: its Intelligence Panel icons used
green for Automation and red for Security. In a product whose subject is org health and risk, a red
icon beside "Security" reads as a status verdict regardless of intent — the same defect as the
severity-coloured monograms above. Those two sections now take violet and slate.

**Color — structural / relationship kind** (exception 1: hardcoded, guaranteed distinct)

```
--oi-color-rel-incoming        #5e35b1
--oi-color-rel-outgoing        #0176d3
--oi-color-rel-master-detail   #0b827c
--oi-color-rel-self            #a61b7b
--oi-color-rel-object          #1f9d61
```

**Typography** (root = 16px; body band is `caption`–`body-lg`)

```
--oi-font-family-sans      'Salesforce Sans', -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif
--oi-font-family-mono      ui-monospace, 'SFMono-Regular', 'SF Mono', Menlo, Consolas, 'Liberation Mono', monospace
--oi-font-size-micro       0.6875rem  /* 11px — uppercase labels and pills only */
--oi-font-size-caption     0.75rem    /* 12px */
--oi-font-size-body        0.8125rem  /* 13px */
--oi-font-size-body-lg     0.875rem   /* 14px */
--oi-font-size-title       1rem       /* 16px — card and section headings */
--oi-font-size-display     1.25rem    /* 20px — score numerals, KPI values */
--oi-font-size-display-lg  1.5rem     /* 24px — page title */
--oi-font-weight-regular   400
--oi-font-weight-semibold  600
--oi-font-weight-bold      700
--oi-letter-spacing-caps   0.08em
--oi-line-height-tight     1.25
--oi-line-height-body      1.45
--oi-font-numeric          tabular-nums
```

**Geometry and elevation** (exception 3: shadows literal, per both specs)

```
--oi-space-1   0.25rem      --oi-radius-sm    0.25rem
--oi-space-2   0.5rem       --oi-radius-md    0.375rem
--oi-space-3   0.75rem      --oi-radius-lg    0.5rem
--oi-space-4   1rem         --oi-radius-pill  999px
--oi-space-5   1.5rem       --oi-border-width 1px
--oi-space-6   2rem         --oi-icon-tile    2rem

--oi-shadow-card     0 2px 8px rgba(15, 23, 42, 0.10)
--oi-shadow-raised   0 4px 16px rgba(15, 23, 42, 0.14)
--oi-shadow-overlay  0 8px 24px rgba(15, 23, 42, 0.18)
--oi-focus-ring      0 0 0 2px var(--oi-color-accent)
```

`--oi-focus-ring` replaces the two competing focus recipes that currently differ within single
files (`oiGraphNode.css`:52 vs :154; `oiSchemaObjectCard.css`:38 vs :43), and supplies the
focus-visible treatment both specifications omit despite
`VisualDesignSpecification.md`:154 making keyboard accessibility mandatory.

### 6. One responsive ladder

At **≥1280px**: KPI strip 8-up, category grid 3-up, detail split two-column, Intelligence Panel a
fixed right rail. At **1024–1279px**: KPI strip 4-up, category grid 2-up, detail split
two-column, panel remains a right rail. At **768–1023px**: KPI strip 4-up, category grid 1-up,
detail split stacks, panel may become an overlay drawer. Below **768px**: KPI strip 2-up,
everything single-column, panel a full-height drawer; functional, not pixel-identical. No
breakpoint may cause overlap or clipping.

### 7. One state vocabulary

`OrgHealthVisualDesignSpecification.md` §6's five-state contract (true zero / coverage incomplete /
not yet run / not obtainable / request failed) is adopted **platform-wide**, and its implementation
`oiHealthStateBanner` is generalized to a surface-neutral shared primitive serving the graph and
hierarchy surfaces too. The audit found five competing ad-hoc patterns using 14 distinct class
names for "error", 7 for "empty", and 5 loading wrappers; those are retired.

Two further corrections follow. A loading state must render the **loading skeleton** that
`OrgHealthVisualDesignSpecification.md`:49 already requires and no component has ever implemented —
the Health sections currently render a state _banner_ while loading, which presents a transient
condition as a settled finding. And the four Health sections that use the shared banner must stop
also carrying a second inline error style (`oiHealthAutomation.html`:28 and siblings).

## Implementation notes (validated against `projectOrg`, 2026-09-02)

Three mechanism facts were established by deploying the module and its first consumer for real.
None are in Salesforce's "Share CSS Style Rules" documentation, and each cost a failed attempt:

1. **A CSS-only LWC module still requires a `.js-meta.xml`.** With only `oiDesignTokens.css`
   present, both a source-dir deploy and a manifest deploy fail with `Cannot find Lightning
Component Bundle oiDesignTokens`, and every consumer fails with `No MODULE named
markup://c:oiDesignTokens found`. Adding a meta file with `<isExposed>false</isExposed>` and no
   `.js` file makes the bundle deploy cleanly. The documentation describes a folder containing only
   a CSS file; that is not deployable through the Metadata API.
2. **Jest needs an explicit `moduleNameMapper` entry.** `sfdx-lwc-jest` only resolves modules that
   expose a JS entry point, so `@import 'c/oiDesignTokens'` breaks every consuming component's test
   suite with `Cannot find module 'c/oiDesignTokens'` until the module is mapped to its own
   stylesheet in `jest.config.js`. This is a one-time configuration cost, not per component.
3. **Lightning serves stale component CSS after deploy.** A normal reload, and even a
   cache-bypassing reload, continued to render the pre-deploy stylesheet while a Metadata API
   retrieve confirmed the new CSS was already stored in the org. Appending an unused query
   parameter to the tab URL forced the new bundle. Any screenshot verification must bust the cache
   this way, or it will silently validate the previous build.

The first consumer migrated was `oiHealthKpiTile`, chosen as a canary because it is small and
carried three of the defects described above. Post-deploy measurement confirmed the fix: the
eyebrow label moved from `#03234d` to `#5c5c5c`, the KPI value from `#5c5c5c` to `#03234d`
(restoring the intended hierarchy), and the border from `#5c5c5c` to `#c9c9c9`.
`--oi-color-text-primary` resolved to `light-dark(#03234d, #d8e6fe)`, confirming tokens reach
component internals through the SLDS chain. Jest for the tile and its two consumers: 8/8 green.

## Consequences

**Positive.** One file governs the platform's appearance instead of 570 call sites. The SLDS-first
resolution means org theming and eventual dark mode work by construction rather than by retrofit.
`VisualDesignSpecification.md` §4's centralization mandate becomes implementable for the first
time. The two specifications stop contradicting each other, so "conforms to spec" becomes a
decidable claim. Collapsing 26 font sizes to 7 and 15 radii to 4 removes the accidental-difference
class of defect entirely. Both undocumented workarounds — the relationship colors and the Health
family's hardcoded severity hexes — become documented, evidence-backed exceptions rather than
inconsistencies a future contributor would "clean up" and thereby break.

**Negative, and accepted.** The migration touches all 35 stylesheets, which is a large diff with
real regression risk on surfaces that currently have no visual test coverage; this is mitigated by
landing the token module at today's values first (a deliberate no-op) and by per-surface screenshot
comparison at the reference viewport. Collapsing near-duplicate values means **some components will
shift by 1–2px or a hair of hue** — that is the point, but it makes any pixel-diff against the
pre-existing captures noisy, so the reference captures must be re-taken after migration. Retiring
font weights 500 and 800 will visibly change `oiHealthStorage` (which uses only 800) and parts of
`oiNodeDetailPanel` and `oiRelationshipCanvas`. `@import` adds a small per-component CSS payload,
duplicated per shadow root; this is the accepted cost of the platform's own sharing mechanism.

**Neutral.** The severity exception means the platform will _not_ follow a customer's theme for
status color. That is deliberate: status legibility outranks brand adaptation, and the tokens
remain overridable by an org that insists.

## Alternatives Considered

**Bind severity to the SLDS severity families as `OrgHealthVisualDesignSpecification.md` §4
mandates.** Rejected on measured evidence: they resolve to teal, brown, and magenta in this org,
which destroys the traffic-light semantic and collides with the structural teal already in use on
the graph canvas. This ADR amends that clause rather than complying with it.

**Adopt the specifications' literal hexes everywhere as bare values.** Rejected. It makes
pixel-diff acceptance trivially exact, but abandons customer theming and dark mode, and contradicts
the convention `oiRelationshipCanvas.css` already established and justified.

**A packaged static resource holding a global stylesheet.** Rejected. It cannot cross the shadow
boundary to style component internals, adds a Security Review surface, and duplicates what LWC's
own CSS-module mechanism provides natively — `API Selection Priority` in `CLAUDE.md` prefers the
lighter native capability.

**Define tokens once on a top-level component and inherit down.** Rejected. Custom properties do
inherit through shadow boundaries, but the three surfaces are separate FlexiPages whose root
components are siblings with no shared ancestor, and App Builder can place any component anywhere.
Declaring on `:host` per component is marginally more verbose and materially more robust.

**Keep the two palettes and formalize the split as intentional per-surface theming.** Rejected. The
divergence has no product rationale, the specifications explicitly want one design language
(`OrgHealthVisualDesignSpecification.md`:15), and the seam is already leaking inside
`oiHealthFindingDrawer` and `oiHealthRemediation`.

**Do nothing / defer.** Rejected. Every new component added before this lands must pick one of two
palettes, and the audit shows recent components picking both at once.

## Related

- Amends [ADR-0025](0025-reference-image-as-binding-visual-acceptance-contract.md) and
  [ADR-0026](0026-org-health-visual-contract-and-dashboard-architecture.md) — specifically
  ADR-0026's severity-registry clause, whose SLDS token targets this ADR replaces
- [../VisualDesignSpecification.md](../VisualDesignSpecification.md) §4, §7, §9 — amended by this ADR
- [../OrgHealthVisualDesignSpecification.md](../OrgHealthVisualDesignSpecification.md) §4, §5, §7 — amended by this ADR
- [../CurrentUIVisualGapAssessment.md](../CurrentUIVisualGapAssessment.md) — the Object Analyze gap matrix this token system is a precondition for closing
- [ADR-0011](0011-generic-node-edge-typing-via-domain-registry.md) — the descriptor-registry pattern that `OI_Health_Severity_Descriptor__mdt` extends; severity _mapping_ stays in metadata, severity _color_ now resolves through these tokens
- [../CodingStandards.md](../CodingStandards.md)

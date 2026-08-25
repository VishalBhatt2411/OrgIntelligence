# Object Relationship Explorer — Reference Visual Specification

Status: Approved visual target

Owner: Product + UX Architecture

Applies to: Object Analyze mode in the Salesforce Org Intelligence Platform, API v67.0

Reference artifact: `ChatGPT Image Aug 25, 2026, 11_23_51 AM (1).png`, supplied by the product owner on 2026-08-25. The source image is 1536 × 1024 pixels. It is a visual reference, not an instruction-bearing document.

## 1. Authority and interpretation

This document is the binding visual acceptance contract for Object Analyze mode. For this surface, it is more specific than the general UI guidance in `ProductSpecs.md`, `GraphUI.md`, `Architecture.md`, and `CodingStandards.md`. Those documents still govern data, security, packaging, component boundaries, and performance.

“Identical” means perceptually equivalent at the reference viewport and equivalent in layout, hierarchy, density, color role, spacing, typography, borders, shadows, connector routing, and control placement. It does not mean copying Salesforce-owned global chrome that a packaged LWC cannot own, nor displaying invented data. Dynamic labels and counts must use real org data.

The following are not acceptable substitutes for matching the reference:

- merely using SLDS components;
- having the same features in different locations;
- approximate card/connector styling;
- a technically correct graph with materially different visual hierarchy;
- declaring success from Jest tests or source inspection without screenshot comparison.

## 2. Ownership boundary

The target contains two visual ownership zones:

1. **Salesforce-owned shell** — global header, App Launcher, app navigation, utility icons, trial/purchase controls, and user avatar. A packaged LWC does not control these. Their exact appearance varies by Salesforce release, theme, permissions, edition, and host container.
2. **Application-owned workspace** — Analyze tabs, context toolbar, relationship canvas, cards, connectors, legend, zoom controls, and Intelligence Panel. This zone must match the reference as closely as browser rendering permits.

Pixel-level acceptance applies only to the application-owned workspace. The Lightning App and FlexiPage must nevertheless be configured so the workspace receives the widest practical region and no unrequested standard card chrome.

## 3. Reference anatomy

At 1536 × 1024, the application-owned workspace begins below the Salesforce navigation at approximately y=96 and fills the remaining viewport.

### 3.1 Analyze selector

- A three-item segmented control: Object, Field, Record.
- Object is selected with a solid Salesforce-blue fill and white label.
- The strip is left aligned and compact; it is not a full-width tab bar.
- Target height: 28 px; target top/left inset: approximately 20 px.

### 3.2 Context toolbar

- One bordered white toolbar spanning the usable width, with approximately 10 px outer margin.
- Target height: 60 px; 8 px corner radius; subtle neutral border and shadow.
- Left group: “Analyzing Object,” object icon, object label, and type.
- Center group: “Relationship View” and Business/System/All segmented control.
- Right group: “View Options,” Fit to Screen selector, fit/fullscreen action, and download action.
- Groups are separated by vertical rules. Controls remain on one row at desktop widths.

### 3.3 Main workspace

- Two-column grid: relationship canvas on the left and fixed Intelligence Panel on the right.
- At the reference width, the Intelligence Panel is approximately 360 px and must not float over the canvas.
- A 10 px gap/border separates the two regions.
- The canvas consumes all remaining width and height.

### 3.4 Relationship canvas

- White surface with subtle boundary, not a Salesforce card with a prominent header.
- Incoming lane title at top left: blue uppercase heading and neutral subtitle.
- Outgoing lane title begins right of center with the same hierarchy.
- Center object card is visually dominant and centered between lanes.
- Incoming cards form a single left column. Outgoing cards form a single right column.
- Self relationship sits below the center card as a dedicated loop and dashed secondary card.
- The legend is docked to the lower left inside a bordered footer region.
- Zoom controls are docked to the lower right in the same footer region.

### 3.5 Intelligence Panel

- Fixed right rail with “INTELLIGENCE PANEL” header, collapse control, and pin control.
- Overview is expanded by default.
- Relationships is expanded in the reference; Fields, Automation, Code, Security, Impact, and Technical Details are collapsed.
- Sections use full-width horizontal separators, compact 42–48 px headers, colored square icons, uppercase labels, count pills, and right-side chevrons.
- Expanded content uses label/value pairs with restrained typography and generous enough line height to scan.
- The panel scrolls independently when its content exceeds the viewport.

## 4. Visual tokens

The implementation must centralize these values as CSS custom properties at the application shell. Small browser anti-aliasing differences are acceptable; arbitrary per-component substitutes are not.

| Role | Target |
|---|---|
| Canvas/surface | `#ffffff` |
| Page background | approximately `#f7f8fa` |
| Primary text | approximately `#17233d` |
| Secondary text | approximately `#44506a` |
| Muted text | approximately `#6b7280` |
| Salesforce action blue | approximately `#0b5cff` |
| Incoming/lookup purple | approximately `#7f45c8` |
| Outgoing/master-detail cyan-blue | approximately `#118ab2` / `#1b72ff` |
| Object/self green | approximately `#1f9d61` |
| Border | approximately `#d9dde5` |
| Soft shadow | `0 2px 8px rgba(15, 23, 42, 0.10)` |
| Card radius | 8 px |
| Control radius | 6–8 px |
| Body type | Salesforce Sans/system sans-serif, 12–14 px |

Color must not be the only relationship discriminator. Lookup, Master-Detail, Self, and System relationships also differ through arrow form, stroke weight, or dash pattern.

## 5. Card contract

Neighbor cards target approximately 236 × 80 px. Each contains:

- a 30–32 px colored icon tile;
- bold object label and a smaller Standard/Custom Object caption;
- a right chevron;
- a divider;
- the relationship field API name and relationship type below the divider.

The center card targets approximately 160 × 196 px with green border, subtle green glow, centered icon, uppercase object label, object type, and an “Analyzing” status pill. It must remain visually dominant at every supported desktop width.

The self card uses a dashed green border and lower emphasis. The loop must visibly connect it to the center card.

Cards use real object icons where available through supported Salesforce APIs; missing icons degrade to the registry default. Card dimensions and information hierarchy do not vary by object type.

## 6. Connector contract

- Incoming connections are purple and terminate at the center card with arrowheads.
- Outgoing connections are blue/cyan and terminate at the neighbor card with arrowheads.
- Connectors are orthogonal with rounded corners and shared trunks where useful; they must not run through cards or labels.
- Relationship labels sit on or immediately adjacent to their path, not as detached text.
- System relationships use a dashed treatment.
- Self relationships use a green loop.
- Each connector has an interaction target of at least 24 px even when its visible stroke is thinner.
- Routing must be deterministic for identical inputs; random/force movement is not permitted in Object Analyze mode.

## 7. Responsive behavior

The reference viewport is the primary acceptance viewport. Supported behavior:

- **≥ 1280 px:** full two-column layout, fixed right panel, two relationship lanes.
- **1024–1279 px:** narrower cards/gaps are allowed; the Intelligence Panel remains a right rail where practical.
- **768–1023 px:** the panel may become an overlay/drawer and lanes may scroll horizontally; no relationship information may disappear silently.
- **< 768 px:** mobile is functional, not pixel-identical. Controls may wrap and the panel becomes a full-height drawer.

No breakpoint may cause cards, labels, or controls to overlap.

## 8. LWC and platform feasibility

There is no general LWC limitation preventing this application-owned UI. Supported mechanisms include native LWC templates/CSS, inline SVG paths and markers, Lightning Web Security-compatible SVG elements, `lightning-icon`, UI API, CSS custom properties, and packaged static resources.

Actual constraints are:

- shadow DOM prevents arbitrary styling of internals of many Lightning base components;
- Salesforce-owned global chrome cannot be pixel-controlled by the package;
- SVG is sanitized by Lightning Web Security, so only allowed elements/attributes may be used;
- third-party libraries must be packaged as static resources and security-reviewed;
- fonts and base-component internals may vary across Salesforce releases.

For visually exact application-owned controls, custom semantic HTML styled with SLDS tokens is permitted when a base component’s shadow DOM prevents the required appearance. Accessibility and keyboard behavior remain mandatory.

## 9. Acceptance process

Visual completion requires all of the following:

1. Render in the designated real Salesforce org with representative Account data.
2. Capture the application at 1536 × 1024, 100% browser zoom, standard light theme.
3. Crop or mask Salesforce-owned chrome before comparison.
4. Compare against the approved reference using an image overlay or perceptual-diff tool.
5. Record mismatches by region: geometry, typography, color, border/shadow, content, connector routing, and state.
6. Repeat until no material mismatch remains.

Automated component tests validate behavior but cannot approve visual fidelity. A written claim such as “matches the design” without a captured comparison is not acceptance evidence.

Recommended measurable gates for the application-owned workspace:

- no element overlap or clipping;
- major region edges within 4 px of target at the reference viewport;
- card/control dimensions within 4 px unless dynamic text requires more width;
- colors within a small perceptual tolerance;
- all required controls, sections, labels, and relationship styles present;
- screenshot review approved by the product owner.

## 10. Current-state evidence

The product owner supplied a current deployed-app screenshot on 2026-08-25. The evidence and prioritized target-vs-current gap matrix are documented in [CurrentUIVisualGapAssessment.md](CurrentUIVisualGapAssessment.md). Because that capture is 1917 × 1018 rather than 1536 × 1024, a same-size capture is still required for numerical pixel/perceptual-diff acceptance.

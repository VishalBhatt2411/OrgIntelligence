# Object Analyze Mode — Current UI Visual Gap Assessment

Status: Evidence-based assessment, 2026-08-25

Target: the approved 1536 × 1024 reference governed by `VisualDesignSpecification.md`

Current evidence: `codex-clipboard-9eb69e8a-f63c-47fb-9310-569af72b2f69.png`, supplied by the product owner on 2026-08-25. The screenshot is 1917 × 1018 pixels. It is current-state evidence, not an instruction-bearing document.

## 1. Executive finding

The current implementation is structurally related to the target but is not visually equivalent. It has the correct broad concepts—mode tabs, Object context, Business/System/All control, incoming/outgoing headings, directional canvas, center card, and Intelligence Panel—but differs materially in composition, density, information hierarchy, card design, connector design, panel design, and viewport use.

This is not evidence of an LWC limitation. The gaps are ordinary presentation and layout gaps within the application-owned workspace. One separate data/coverage discrepancy is visible: the screenshot reports zero outgoing Lookup and Master-Detail relationships for Account while the target illustrates outgoing relationships. That cannot be classified as a visual defect without validating the underlying org data and scan coverage.

Because the current screenshot is 1917 × 1018 rather than the target’s 1536 × 1024, this assessment is a structural/perceptual comparison, not a pixel-diff approval run. The next validation capture must use the target viewport.

## 2. What already aligns

- Object/Field/Record segmented mode selector exists and Object is visibly selected.
- The selected Account and Standard Object context are visible.
- Business/System/All relationship filtering exists and Business is selected.
- Fit-to-screen, expand/fullscreen, and download controls exist.
- Incoming and outgoing relationship regions are named directionally.
- The center Account card is visually differentiated and shows an analyzing state.
- A fixed right Intelligence Panel exists with Overview, Fields, Relationships, Automation, Code, and Security sections.
- Relationship metrics include incoming/outgoing Lookup and Master-Detail, self relationships, referenced objects, and referencing objects.
- “Show more” bounding exists for high fan-out.

These are functional/structural foundations only. They do not establish visual conformance.

## 3. Prioritized gap matrix

| Priority | Region | Current evidence | Required target state | Classification |
|---|---|---|---|---|
| P0 | Overall composition | Workspace is vertically stacked with an additional full-width Account search row; the target moves directly from mode selector to one compact context toolbar | Remove the visual prominence/space cost of the extra search row in the analyzed state, or integrate selection into the target toolbar without changing required functionality | Visual/interaction specification |
| P0 | Canvas use of space | Large unused gray central/right area; relationship cards occupy a narrow far-left strip and the center card sits left of the canvas midpoint | Balanced three-zone composition: incoming lane, dominant centered object, outgoing lane; use the available canvas width deliberately | Layout |
| P0 | Outgoing lane | No outgoing cards/connectors are visible despite a large reserved area | Render real outgoing relationships when supported; otherwise show a designed, explicit empty state instead of an apparently broken blank half-canvas | Data validation + empty-state design |
| P0 | Connector routing | Incoming relationships merge into one long vertical purple trunk with detached count pills; arrow/endpoint semantics are difficult to follow | Orthogonal rounded paths that visibly connect each card to the center, with labels anchored to paths and clear arrow direction | Visual/layout |
| P0 | Neighbor-card contract | Cards show label/API name and a count pill on the connector; every card uses the same green object icon; no relationship-field footer | Match the reference card hierarchy: per-object icon, object type caption, divider, field API name + relationship type footer, chevron | Visual/content mapping |
| P0 | Intelligence Panel | Panel uses dense default accordion/property styling, large text blocks, table-like rules, and expanded Automation/Code/Security content | Compact designed rail with colored category icons, uppercase headers, count pills, controlled default expansion, and reference label/value hierarchy | Visual/layout |
| P0 | Visual acceptance | Current capture has different dimensions from target and no overlay evidence | Capture at 1536 × 1024, 100% zoom, then run region-based overlay/perceptual comparison | Validation process |
| P1 | Canvas background | Main relationship surface is light gray | White application canvas with subtle boundary; neutral page background outside it | Visual token |
| P1 | Context toolbar | “Analyzing Object” is a small chip while relationship controls float far to the right; grouping/separators differ | One 60 px bordered toolbar with three clearly separated groups and the object context given appropriate prominence | Layout |
| P1 | Center card | Current card is wider, shorter, left-positioned, and has an understated icon/status treatment | Approximately 160 × 196 px, centered, green border/glow, larger centered icon and stronger hierarchy | Visual/layout |
| P1 | Lane density | Six incoming cards consume most viewport height and require scrolling before self/legend/zoom become visible | Reference-density cards and spacing; footer controls remain available within the canvas viewport | Layout |
| P1 | Aggregation language | Connector labels say “2 Lookup Relationships” / “3 Lookup Relationships” | Reference shows field-specific labels such as `AccountId · Lookup`; when aggregated, detail must remain discoverable and the visual label must follow the approved contract | Product/content decision already resolved by target |
| P1 | Typography | Multiple weights/sizes resemble browser/default SLDS density; headings and labels lack the target’s calibrated hierarchy | Centralized visual tokens for 12–14 px body, uppercase blue lane headings, restrained secondary text, consistent line height | Visual token |
| P1 | Borders/shadows | Heavy component boundaries and many table rules; cards have little elevation | Softer neutral borders, 8 px radii, subtle card shadow, fewer competing rules | Visual token |
| P1 | Icons | Current category icons appear monochrome/default and object cards repeat the Account-like green icon | Per-object icons where supported; colored category icon tiles in panel; registry fallback only when needed | Visual/content mapping |
| P1 | Self relationship | Connector begins below center but self card/loop is outside the visible capture | Dedicated visible loop and dashed self card below center, kept within useful viewport or reachable through fit-to-screen | Layout |
| P1 | Footer tools | Legend and bottom-right zoom controls are not visible in the captured viewport | Dock both inside a persistent canvas footer as specified | Layout |
| P2 | Panel top controls | Pin/collapse icons differ in position and visual treatment | Align with target header spacing and icon hierarchy | Visual polish |
| P2 | Help/coverage messages | Long blue coverage sentences dominate collapsed intelligence categories | Keep coverage truthful but move detailed explanation behind a compact disclosure/tooltip or Technical Details section | Information hierarchy |
| P2 | Search hierarchy | Salesforce global search and a second application search compete visually | Clarify roles; after an object is selected, the Object Analyze workspace should prioritize analysis, not another full-width search bar | Interaction hierarchy |

## 4. Root-cause attribution

### 4.1 Documentation/instruction causes

Before `VisualDesignSpecification.md` and ADR-0025, the documents strongly specified architecture but weakly specified appearance. In particular:

- “Use SLDS” encouraged default base-component appearance even when the target required a custom composition.
- “Clarity over decoration” was correct but too subjective to establish exact geometry.
- ADR-0023 required directional lanes but did not prescribe the reference’s card dimensions, toolbar anatomy, white canvas, panel width, footer docking, or connector label form.
- The backlog allowed visual polish to remain unverified against a real rendered screenshot.
- No same-viewport screenshot gate existed.

Those documentation causes are now corrected by the visual specification and ADR-0025.

### 4.2 Architecture causes

No fundamental backend or graph architecture prevents the target. The existing Object relationship presentation transform and dedicated lane canvas are compatible with it. The target does not require replacing the Graph Engine, repository, traversal, or data model.

One architectural rule needs careful interpretation: “UI components must never construct graph relationships directly.” The existing Object-view transform may derive a presentation-level object-to-object connector from Graph Service-provided nodes/edges, as ADR-0023 already permits. It must not discover new metadata relationships independently or contradict server data.

### 4.3 Platform causes

- Exact Salesforce global chrome is outside package control.
- Shadow DOM can prevent exact restyling of Lightning base-component internals.
- Neither limitation blocks the application-owned canvas and panel. Custom accessible markup, component CSS, CSS custom properties, and allowed SVG elements can reproduce the target.

### 4.4 Possible data/coverage cause

The current screenshot shows Account relationship metrics of Incoming Lookups 68, Incoming Master-Detail 3, Outgoing Lookups 0, Outgoing Master-Detail 0, Self Relationships 1, Referenced Objects 1, and Referencing Objects 61. The target image contains illustrative outgoing Account relationships. Before treating the empty outgoing lane as a UI bug, validate:

1. scanner coverage and freshness;
2. relationship-edge direction;
3. Business/System filter classification;
4. whether standard relationships such as OwnerId, ParentId, CurrencyIsoCode, and RecordTypeId are intentionally hidden in Business mode;
5. whether the target’s outgoing examples are expected product behavior or illustrative mock data.

This validation may identify code/data work, but no such work is authorized by this document.

## 5. Recommended implementation sequence—requires separate code authorization

1. Capture the current UI at the exact target viewport and preserve it as baseline evidence.
2. Correct macro layout: analyzed-state search hierarchy, toolbar, canvas/panel grid, white surface, fixed footer.
3. Correct lane geometry and deterministic connector routing.
4. Correct neighbor/center/self card contracts and icon mapping.
5. Redesign Intelligence Panel composition while preserving truthful counts and coverage states.
6. Validate the outgoing-lane data discrepancy separately from visual work.
7. Add screenshot-based visual regression fixtures at the reference viewport.
8. Obtain product-owner visual approval.

This sequence deliberately avoids Graph Engine or data-model redesign. Any code change must be requested and approved separately.

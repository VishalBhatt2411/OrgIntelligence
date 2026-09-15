# Cross-Surface UI Consistency Pass — Execution Checkpoint

Working log for the ADR-0028 design token migration. This file exists so work can resume precisely
across context windows, mirroring `OrgHealthProductionizationProgress.md`'s role. Update the
checklist as each item lands; do not remove history — mark it done and move on.

Verification contract for this pass: deploy to `projectOrg` and confirm by screenshot at
1536 × 1024. **Always append an unused query parameter** (e.g. `?cachebust=<date>`) when
re-checking a deployed change — Lightning otherwise serves the previous stylesheet and the
screenshot silently validates the old build.

## Phase 0 — Reconcile the visual contract

- [x] `docs/ADR/0028-unified-cross-surface-design-token-system.md` written and indexed in
      `docs/ADR/README.md`. Resolves 12 conflicts (C1–C12) between the two visual specifications,
      defines the canonical `--oi-*` vocabulary neither document had, and records the live token audit.
- [x] `VisualDesignSpecification.md` amended: §4 token table → canonical token names; the
      ambiguous single "outgoing/master-detail" role split into two tokens; the 12–14px band scoped to
      body text; §5 icon tile → `--oi-icon-tile`; §7 marked as the platform's only ladder.
- [x] `OrgHealthVisualDesignSpecification.md` amended: §4 three text roles restored, severity table
      rewritten around the falsified audit, §5 rem values → tokens, §3.2/§3.3/§7 breakpoints collapsed
      onto 1280/1024/768 (620/640/980 deleted, the 768–1023px 2-up/1-up contradiction resolved to
      1-up), acceptance viewport fixed at 1536 × 1024.

## Phase 1 — Token module

- [x] `force-app/main/default/lwc/oiDesignTokens/` created (CSS-only module + required
      `.js-meta.xml`) and deployed to `projectOrg`.
- [x] `jest.config.js` given a `moduleNameMapper` entry for `c/oiDesignTokens`.
- [x] Canary migration `oiHealthKpiTile` deployed and verified by measurement — three live defects
      fixed (see ADR-0028 Implementation notes). Jest 8/8 green for the tile and its two consumers.

## Phase 2 — Migrate components onto tokens

Order chosen so the two palettes converge from the _smaller_ family inward, and so shared
primitives land before the sections that compose them.

- [x] Shared Health primitives: `oiHealthSeverityBadge`, `oiHealthScoreRing`,
      `oiHealthStateBanner`, `oiHealthBreakdownList`, `oiHealthHeatmapGrid`,
      `oiHealthFormulaDisclosure`
- [x] Health sections: `oiOrgHealthDashboard`, `oiHealthOverviewGrid`, `oiHealthSectionNav`,
      `oiHealthMetadata`, `oiHealthAutomation`, `oiHealthCode`, `oiHealthSecurity`, `oiHealthData`,
      `oiHealthStorage`, `oiHealthRemediation`, `oiHealthFindingDrawer`
- [x] Graph family: `oiGraphExplorer`, `oiGraphCanvas`, `oiGraphNode`, `oiSchemaObjectCard`,
      `oiNodeDetailPanel`, `oiRelationshipCanvas`, `oiRelationshipConnectorDetail`, `oiFilterPanel`,
      `oiIntelligenceDrilldown`
- [x] Hierarchy family: `oiHierarchyManager`, `oiHierarchyViewer`, `oiHierarchyTree`,
      `oiHierarchyTreeNode`, `oiHierarchyPath`, `oiHierarchySwitcher`
- [x] `oiSearchBar` + `oiRecordPicker` — **plan corrected**: these are NOT collapsed into one
      component. ADR-0017 deliberately keeps record search outside the graph
      (`OI_SearchController.search` over metadata nodes vs `OI_RecordSearchController.searchRecords`
      over records), so merging them would erase an intentional architectural boundary. What was
      genuinely duplicated was the _styling_, so a second CSS-only module `c/oiComboboxStyles` now
      holds the shared search-box-with-suggestion-panel pattern and both templates use its
      `oi-combobox*` vocabulary. One test selector renamed accordingly.
- [x] Retire the duplicate `--oi-node-accent` definitions — the two components no longer disagree,
      and both JS colour maps now resolve the same `--oi-*` tokens
- [x] Delete the dead webfont declarations (`Manrope`, `IBM Plex Sans`, `IBM Plex Mono`, plus three
      competing monospace stacks) — done for every Health and Hierarchy component; graph family
      in progress

### Added during Phase 2: a fourth color channel

Binding **identity** to **severity** was found to produce actively misleading UI — the Org Health
landing grid coloured Code Health's monogram severity-green and Data Health's severity-amber as
fixed properties of the section, contradicting their real scores (58 and 95) rendered inches away.
ADR-0028 §5 now defines `--oi-color-identity-1..6` (+ washes) as a categorical channel that
excludes green and red by construction, and `oiHealthOverviewGrid.js` consumes it.

- [x] Migrated `oiNodeDetailPanel`'s metadata-type accents onto the identity ramp (extended to
      seven slots). Two hues changed deliberately: the block used **green for Automation and red for
      Security**, which in a health/risk product reads as a status verdict — the same defect class as
      the Org Health monograms. Automation is now violet, Security slate. Verified live: all seven
      sections resolve identity tokens, none green or red.

### Phase 2 verification (2026-09-02)

Full Jest **42 suites / 471 tests green**. ESLint reports 11 errors, all pre-existing and unrelated
(async-operation and arrow-function rules); three of the files involved are tracked and unmodified
in the working tree, the other two are new files from the in-flight Org Health work, and none were
touched by this migration. Deployed to `projectOrg` (45/45 components, 0 errors) and all three
surfaces checked live.

Measured corrections confirmed in the browser: severity badges render true green `#2e844a` on a
green wash (previously mint-on-teal via SLDS `success-container-1`/`success-1`); the six Org Health
monograms render six distinct identity hues with no green or red; KPI values now outweigh their
labels. Scores read 82 / 98 / 95, all correctly in the Good band — the severity mapping is sound.

Two verification hazards worth remembering, both of which produced a wrong reading first time:

1. **A URL query parameter is not always enough to bust Lightning's cache.** The Intelligence
   Panel served the _committed_ stylesheet through a cache-busted load; a Metadata API retrieve
   proved the correct CSS was already in the org. Clearing IndexedDB/localStorage and reloading
   fixed it. Always confirm against a retrieve before concluding a deploy did not take effect.
2. **Do not read colours or numerals off a downscaled screenshot.** An 800px capture led to
   reading a score of 98 as 58 and a `lightning-icon` tile as changed when it had not been. Probe
   `getComputedStyle` instead.

## Phase 3 — Unify the state layer — COMPLETE

- [x] Generalized `oiHealthStateBanner` into the surface-neutral `c/oiStateBanner`; adopted on all
      three surfaces and the old bundle deleted. `retryable` is now a property of the _state_ (only
      `error`), so "not obtainable" can never render a Retry that could not succeed, and `ariaRole`
      returns `alert` for `error` / `status` otherwise, preserving the announcement semantics of the
      hand-rolled `role="alert"` patterns it replaced.
- [x] Built `c/oiSkeleton`, the loading placeholder OHVDS §3.4 required and nothing implemented.
      Health sections previously rendered a five-state _banner_ reading `not-yet-run` + "Loading …"
      while a request was in flight, presenting a pending request as a settled finding — and colliding
      with the genuinely different condition of a scan that has never run.
- [x] Removed the duplicate inline error style from the four Health sections that also used the
      shared banner; `.oi-health-sync-error` deleted from each.
- [x] Retired the ad-hoc error/empty/loading class names across all three surfaces.
- [x] Reconciled `oiNodeDetailPanel`'s four-variant empty-state badge vocabulary. The compact badge
      was kept (a card-shaped banner per category would dominate a 360px rail) but its variants now
      collapse onto the canonical keys via `CANONICAL_STATE_BY_EMPTY_KIND` and are exposed as
      `data-state`. All four _messages_ survive, so the distinctions the colour no longer draws are
      still stated in words.
- [x] `oiScanStatusPanel` got its first stylesheet and an honest loading treatment: a skeleton for
      the initial fetch (it previously claimed "Status: No scans yet" before the fetch resolved — a
      false statement, not a loading state) and an inline `role="status"` busy label for an in-flight
      start/cancel, where the content is present and only the button is pending.
- [x] Split `not-obtainable` out of the finding drawer's `navigationError`. A finding with no
      `componentKey` hit a guard that re-running could never pass, so the banner had been offering a
      Retry that was guaranteed to fail identically.
- [x] Added the definitions-list confirmed zero in `oiHierarchyManager`. The levels and
      relationships lists each stated their own zero; the definitions list did not, so an org with no
      hierarchies rendered an empty void under the "Hierarchies" heading — indistinguishable from a
      list that had failed to load. Found by looking at the deployed page, not the code.

Deliberately not converted, and why: idle prompts ("Search for an object…", "Select a node to see
its details") are not one of the five states — none of them means "you have not chosen anything
yet"; a permission message is an authorization fact, not a data state; and
`.oi-health-selection-note` is genuinely ambiguous between a clean component and one never synced,
so it was left rather than have a state invented for it.

## Phase 4 — Lift Hierarchy Manager — COMPLETE

- [x] The surface now sits on a card (surface, border, radius, `--oi-shadow-card`, padding) and
      states its own text baseline instead of inheriting the host FlexiPage's.
- [x] Deliberately **no** in-component page header: Lightning renders the tab label as the App Page
      header, so a title here would print the page name twice — the very duplication Phase 5 removes
      from Org Health.
- [x] Buttons moved to the new shared `c/oiButtonStyles`. The four form buttons that carried no
      class at all — and so rendered as raw browser chrome beside styled siblings — joined the
      vocabulary, and the accent fill was narrowed to the two actions that actually commit a form:
      "New", "Add Level" and "Assign Relationship" merely _open_ one, so four filled accent buttons had
      been competing on one screen with no hierarchy between them.
- [x] Fixed the `oiHierarchyTreeNode` focus indicator: `:focus-visible` had set `outline: none` and
      signalled focus only with a background tint, indistinguishable from a stray mouse position. It
      now carries `--oi-focus-ring`.

### `c/oiButtonStyles` — why it exists

`.oi-health-btn` had been copy-pasted into eight stylesheets and the copies had **drifted**. Three
(Automation, Metadata, the Org Health dashboard) carried no `:focus-visible` rule at all, so their
buttons showed no focus indicator — an accessibility defect VDS §8 forbids, visible only by diffing
the eight copies against each other. Three omitted `font-family`/`line-height`, so the same button
rendered at a different size depending on the section; the `-primary` variant existed in only two.
The module defines exactly three variants (`.oi-btn`, `.oi-btn_primary`, `.oi-btn_link`).

It deliberately does **not** set `align-self`. Doing so would have fixed the Hierarchy Manager's
full-width Save button in one line, but the same declaration drags the Org Health header's Refresh
button off centre in that flex row — so column geometry is stated by the component that owns the
column.

## Phase 5 — Branding and shell

- [x] Distinct tab motifs — all three tabs used `Custom1: Heart`, so every surface showed the same
      heart glyph. Now `Custom4: Radar` (Graph Explorer), `Custom16: Compass` (Hierarchy Manager),
      `Custom15: Chart` (Org Health). `motif` is a fixed platform enum, so candidates were confirmed
      with a check-only deploy (`--dry-run`) rather than assumed valid.
- [x] Renamed the Graph Explorer tab from `Org Intelligence` to `Graph Explorer`. Its label was
      identical to the `CustomApplication` label, so the nav bar printed the same words twice and the
      platform page header never named the page you were on. Tab **API names** are unchanged, so the
      permission-set `tabSettings` that grant visibility are unaffected.
- [ ] Resolve the duplicated page header. The FlexiPages are not the cause — all three are a bare
      `flexipage:defaultAppHomeTemplate` with no header component. Lightning renders the _tab label_ as
      the App Page header, and the components then render their own title beneath it. The fix therefore
      belongs in `oiGraphExplorer` / `oiOrgHealthDashboard`, not in the FlexiPage. Deferred until the
      Phase 3 state-layer work on those two components lands, to avoid editing them concurrently.

## Testing gate after each group

Focused Jest for the touched components, then deploy to `projectOrg` and screenshot at the
reference viewport with a cache-busting parameter. Full Jest + lint + full-`force-app` deploy
validation once at the end of each phase.

## Key facts discovered this pass (avoid re-deriving)

- There are now **three** CSS-only modules: `c/oiDesignTokens` (the token vocabulary),
  `c/oiComboboxStyles` (the search-box + suggestion-panel pattern) and `c/oiButtonStyles` (the
  native-button vocabulary). Every new one needs an entry in `jest.config.js`'s `moduleNameMapper`
  alternation or every consumer's suite fails to resolve it.
- Busting the Lightning CSS cache with a query parameter is **not** always enough. After a deploy
  the reliable sequence is: delete the IndexedDB databases (`ldsDurableCache`, `actions`, et al.)
  and clear local/session storage, then reload with a fresh query parameter. Two verification
  passes this session showed unchanged markup _and_ CSS until the databases were dropped — twice I
  nearly recorded a working change as broken.
- **A pre-existing intermittent test failure exists and is not caused by this pass.** `npx jest`
  (43 suites / 506 tests) fails 1–2 tests in roughly half of full runs, always in
  `oiIntelligenceDrilldown` or `oiRelationshipConnectorDetail`, always an assertion that
  `navigateToTarget` was called. Established: it passes 8/8 in isolation; it reproduces under
  `--runInBand` and `--no-cache`; widening the `flushPromises` helper to five macrotask turns did
  **not** help (that change was reverted); and it still occurs with
  `oiRelationshipConnectorDetail.test.js` reverted to be byte-identical to `HEAD`. A timing
  explanation does not fit the record-mode case, where `navigateToTarget` is called synchronously
  with no `await` before it. Every other suite passes every run. Tracked separately — do not treat
  a red full-suite run as a regression without checking which test failed.
- A CSS-only LWC module **must** ship a `.js-meta.xml` (`isExposed=false`, no `.js`) or the bundle
  will not deploy — contrary to the "Share CSS Style Rules" documentation.
- `sfdx-lwc-jest` cannot resolve a CSS-only module; it needs a `moduleNameMapper` entry.
- Lightning serves stale component CSS after a successful deploy, defeating even a cache-bypassing
  reload. Bust it with a query parameter.
- In SLDS 2, `--slds-g-color-on-surface-1` is the **weakest** text tier (`#5c5c5c`) and `-3` the
  **strongest** (`#03234d`). Several components assumed the reverse and rendered labels stronger
  than the values they label. Likewise `--slds-g-color-border-2` is the **strong** border
  (`#5c5c5c`), not the subtle one — `border-1` (`#c9c9c9`) is subtle.
- Severity tokens in this org are teal/brown/magenta, not green/amber/red; root font size is 16px;
  `color-scheme` is `normal` so never use a `prefers-color-scheme` media query. Full evidence in
  ADR-0028 Context.

# Org Health Productionization — Execution Checkpoint

Working log for the multi-domain Org Health production directive (post ADR-0027). This file exists
so work can resume precisely across context windows, per the directive's own allowance
("continue autonomously using repository documentation/checkpoints"). Update the checklist as each
item lands; do not remove history — mark it done and move on.

## Corrections (must land before any new domain work)

- [x] **Metadata classification fix** (code + dedicated unit tests green against entTrial:
      OI_MetadataClassificationServiceTest, OI_MetadataHealthServiceTest) — replace `OI_MetadataHealthService.classifyObject` (naming-convention regex against `Label__c`, which is the _friendly label_, not the API name — a latent bug beyond just "unreliable") with a bulk, authoritative `OI_MetadataClassificationService` backed by `EntityDefinition.PublisherId`/`NamespacePrefix`, queried once for the whole object set (never per-object). Four classification values: Salesforce Standard / Unmanaged Custom / Managed Package / Unknown-Insufficient Metadata. Standard objects stop being suppressed outright — their _custom_ field count (fields whose API name ends `__c`, a hard platform invariant, unlike object-level `__c` which is ambiguous between org-custom and managed) still counts toward High Field Count; their connectivity/automation/security/code signals are unaffected by classification at all (those never excluded standard objects to begin with).
- [x] **Multi-signal severity engine** (OI_HealthScoringEngineTest green against entTrial; adopted
      by Metadata Health AND Automation Health so far) — new `OI_HealthScoringEngine` (+ `OI_HealthSignal` input, `OI_HealthScoreResult`/`OI_HealthScoreContributor` output) computing a weighted, confidence- and exposure-aware badness score per finding, storing contributors for the drawer. Correlated signals grouped so they combine by max, not sum. Metadata Health's three rules are the first consumer/proof; Automation/Code/Security ports happen as each domain is touched.

## Finding lifecycle extension

- [x] (code complete, deploy confirmed successful, **Apex-level verification currently BLOCKED**
      by the entTrial schema-propagation anomaly above — OI_OrgHealthFindingRepositoryTest/
      OI_OrgHealthFindingServiceTest/OI_OrgHealthControllerTest's finding-flow tests all fail with
      "No such column 'Score__c'" purely because the org hasn't yet made the field visible to Apex,
      not because of a code defect) New fields on `OI_Org_Health_Finding__c`: `Score__c`,
      `Severity_Contributors_Json__c`, `Resolved_Date__c`, `Risk_Acceptance_Expiry__c`,
      `False_Positive_Justification__c`.
- [x] `enableHistory=true` + `trackHistory=true` on `Status__c`/`Due_Date__c` (native Field History — real mechanism, not fabricated) for status/owner change history; OwnerId history is automatic once object history is on.
- [x] Related findings = same `Component_Key__c`, queried on demand (no junction object). Related graph component = existing `Component_Key__c` resolved through `OI_GraphEngine.getNodeDetail` + the **already-existing** `OI_MetadataNavigationService` (this already covers most of the "Central Navigation Service" requirement — extend it with new component kinds rather than building a second one).
- [ ] Owner picker in `oiHealthFindingDrawer` (was deferred in ADR-0027) — NOT YET DONE.
- [ ] LWC surfacing of score/contributors/resolvedDate/riskAcceptanceExpiry/falsePositiveJustification/relatedFindings/relatedGraphNavigation in `oiHealthFindingDrawer` — NOT YET DONE (backend DTO fields exist; drawer UI not yet updated to show them).

## Domains (vertical slice = rules + candidates + sync + drawer wiring + tests)

- [x] Metadata Health — re-verified after classification/scoring rewrite (all dedicated unit
      tests green against entTrial except the finding-lifecycle read/sync path, blocked by the schema
      anomaly above, not a code defect).
- [x] Automation Health — OI_HealthScoringEngine ported in (replaced graduatedSeverity's raw
      threshold jump with dependencySignal/cycleSignal scored via the shared engine);
      getFindingCandidates() + Controller getAutomationHealthFindings/syncAutomationHealthFindings
      added, mirroring Metadata Health exactly; oiHealthAutomation.js/html wired to the finding
      drawer + sync button, mirroring oiHealthMetadata; Jest (8/8) green. Apex-level finding-sync
      verification also blocked by the same schema anomaly (OI_AutomationHealthServiceTest's own
      detail/candidate tests, which don't touch the Finding object, ARE independently verifiable and
      green).
- [x] Code Health — OI_HealthScoringEngine ported in (replaced graduatedSeverityHighIsBad/
      graduatedSeverityLowIsBad's raw threshold jumps with dependencyScore/apiVersionScore/cycleScore
      computed via the shared engine, same PRIMARY_SIGNAL_WEIGHT=90/CYCLE_SIGNAL_WEIGHT=45 convention
      as Automation Health); getFindingCandidates() (HighDependency/OldApiVersion/DependencyCycle) +
      Controller getCodeHealthFindings/syncCodeHealthFindings added, mirroring Metadata/Automation
      Health exactly; oiHealthCode.js/html/css wired to the finding drawer + sync button (this section
      IS scored — score ring + formula disclosure kept, unlike Automation Health's facts-only header).
      Added OI_CodeHealthService.deriveNodeKey (@TestVisible static) so tests can control a REAL,
      already-deployed class's fan-in/out/cycle evidence via freely-insertable OI_Graph_Edge__c rows
      without needing to fabricate an ApexClass row (impossible via DML) — key discovery: cycle
      detection's selectCurrentEdgesBetweenKeys only counts edges where BOTH endpoints are in the
      scanned class set, so a cycle fixture needs TWO real class names (used OI_HashUtil +
      OI_GraphEngine), not one real class + one arbitrary key. OI_CodeHealthServiceTest 5/5 green
      against entTrial (includes 2 new scoring-engine tests, mirroring Automation Health's). Jest
      9/9 green for oiHealthCode; full suite 432/433 (same pre-existing unrelated oiIntelligenceDrilldown
      flake, not a regression). OI_OrgHealthControllerTest's new
      testSyncCodeHealthFindingsComputesAndPersistsRealFindings correctly exercises the same code path
      and fails ONLY due to the still-open entTrial schema-propagation anomaly (identical
      AuraHandledException as the pre-existing Metadata/Automation Health sync tests) — re-run once
      that clears.
- [x] Security Health — OI_HealthScoringEngine ported in (replaced the removed
      graduatedSeverity/computeSeverityKey raw-threshold statics with elevatedScore/broadGrantScore/
      sensitiveGrantScore computed via the shared engine, each scored independently and combined by
      worstOf — same pattern as Automation/Code Health); getFindingCandidates()
      (ElevatedPermissions/BroadObjectGrant/SensitiveObjectGrant) + Controller
      getSecurityHealthFindings/syncSecurityHealthFindings added; oiHealthSecurity.js/html/css wired
      to the finding drawer + sync button (facts-only header preserved — this section has no score
      ring, Is_Scored__c = false). The "sensitive grant with 0 assignees = Warning, with active
      assignees = Critical" product guarantee is now modeled as confidence=1.0/exposureMultiplier
      (0.5 unassigned, 1.0 assigned) rather than a hardcoded if/else, and verified end-to-end via two
      new fixture-based tests (not a direct static-method call, since the statics were removed).
      Real fixture bug caught by an actual test run: ObjectPermissions.PermissionsModifyAllRecords
      requires PermissionsEdit=true/PermissionsDelete=true set too (FIELD_INTEGRITY_EXCEPTION
      otherwise) — fixed in both new OI_SecurityHealthServiceTest fixtures and the new
      OI_OrgHealthControllerTest fixture. OI_SecurityHealthServiceTest 7/7 green against entTrial
      (2 removed static-helper tests replaced with end-to-end scoring-engine verification, 2 new
      tests added: well-formed-candidates + the two sensitive-grant-severity tests). Jest 8/8 green
      for oiHealthSecurity. OI_OrgHealthControllerTest's new
      testSyncSecurityHealthFindingsComputesAndPersistsRealFindings correctly exercises the same code
      path and fails ONLY due to the still-open entTrial schema-propagation anomaly (identical
      AuraHandledException as the pre-existing Metadata/Automation/Code Health sync tests) — re-run
      once that clears. Broader ADR-0026-named Security areas (network access, session settings,
      native Health Check score, connected/external client apps) are a named future enhancement, not
      built this pass — ProductSpecs.md's own Security Health scope lists exactly the four
      evidence-based checks this slice covers, and none of those broader areas have an existing
      selector/service in this codebase yet (see OI_SecurityHealthService's own class doc).
- [x] Data Health — OI_HealthScoringEngine ported into ObjectSignal.applySeverity (replaced the
      removed graduatedSeverity(ratePercent, thresholdPercent) raw-threshold static with independent
      staleScore/incompleteScore/duplicateScore, each scored via a new rateSignal(...) helper and
      combined by worstOf — same per-rule-independent-score pattern as every other domain). New
      constants PRIMARY_SIGNAL_WEIGHT=90 (shared name) and RATE_SIGNAL_CONFIDENCE=0.7 (a
      domain-specific value, lower than other domains' 0.8, deliberately calibrated by hand so this
      domain's own established "~2x threshold reaches Critical" convention for sampled rates survives
      the port — verified by hand arithmetic against the exact contribution formula
      (weight x min(magnitude,1.5)/1.5 x confidence x impact x exposure), then confirmed for real via
      a passing entTrial test run, not just the calculation. getFindingCandidates(signals) added
      (DataHealth.StaleRecords/Completeness/Duplicates, one candidate per non-Good metric per object);
      Controller getDataHealthFindings() added as a read-only method — Data Health has no separate
      syncDataHealthFindings write method, since OI_DataHealthComputeBatchable's own finish() already
      calls getFindingCandidates() + OI_OrgHealthFindingService.sync() once per bounded async run (the
      domain's only write action is recomputeDataHealth). oiHealthData.js/html/css wired to the finding
      drawer via a clickable breakdown list + onrowselect (same pattern as every other domain), but
      deliberately has no sync button/isSyncing/syncError state, matching the domain's real action
      surface. OI_DataHealthServiceTest: removed testGraduatedSeverityGradesBelowAtAndAboveTheThreshold
      (called the now-deleted static), added testApplySeverityRateSignalCalibrationMatchesEstablished
      SeverityBoundaries (explicit Warning/Critical boundary proof) and two getFindingCandidates tests
      (well-formed candidates for breached rules only; zero candidates for an all-Good signal) — 9/9
      green against entTrial, including the pre-existing
      testBuildSnapshotFromSignalsComputesWeightedPenaltyScoreAndRanksWorstFirst test whose exact
      Contact=Critical/Account=Warning ranking depended on the new calibration and was NOT touched,
      proving the port preserved it. Jest 8/8 green for oiHealthData (rewrote the test file to mock
      the newly-added getDataHealthFindings Apex import — every existing test needed that mock added
      alongside getDataHealthDetail since load() now does Promise.all([...]); added 5 new
      drawer-wiring tests mirroring oiHealthCode.test.js minus the sync-button tests). New
      OI_OrgHealthControllerTest.testGetDataHealthFindingsWithoutPermissionThrowsAuraHandledException
      added and green. OI_DataHealthComputeBatchableTest's existing end-to-end test
      (testExecuteEndToEndAgainstScopedObjectsProducesAWellFormedPersistedSnapshotWithDuplicateDetection)
      now additionally exercises finish()'s new sync(...) call and fails ONLY due to the still-open
      entTrial schema-propagation anomaly (identical `No such column 'Score__c'` AuraHandledException
      root cause as every other domain's sync-path tests) — re-run once that clears; this is not a
      regression, and the anomaly was re-confirmed still active via the probe script
      (HAS_PROBE=false, TOTAL_FIELDS=40) immediately before concluding this domain. Native Duplicate
      Rule/Matching Rule integration remains a named future enhancement, not built this pass —
      ProductSpecs.md's own Data Health scope ("Potential indicators: Record Count, stale records,
      null density, data completeness, high-volume Objects") does not name duplicates as a required
      indicator at all; the existing exact-match Email/Phone heuristic is preserved and honestly
      labeled Low-confidence/review-first in both the finding candidate's explanation text and its
      `confidence` field.
- [x] Storage — audited against ProductSpecs.md's Storage scope, which is exactly and only "Data
      Used, Data Remaining, File Used, File Remaining... if some desired metric is not actually
      obtainable, state it." OI_StorageHealthService.getStorageHealth() already reads both
      DataStorageMB and FileStorageMB from System.OrgLimits.getMap() and reports any absent limit type
      via dto.unavailableMetrics rather than fabricating zero; oiHealthStorage.js/html already render
      all 4 metrics as KPI tiles plus an honest "not exposed by this org's API version" banner for
      anything missing, with the standard error/retry pattern. This section is Tier-1, facts-only, no
      scoring — its own class doc says so explicitly ("No scoring — the spec asks this section for
      facts, not a score") — so there is no rule-breach concept here and therefore no finding
      candidates to build; the unified finding model does not apply to this section, by design, not
      by omission. No code changes were needed — this was already a complete, correctly-scoped vertical
      slice from earlier work; this pass only verified it against ProductSpecs.md's literal wording and
      ran its tests for real: OI_StorageHealthServiceTest 2/2, OI_OrgHealthControllerTest's
      testGetStorageDetailReturnsLiveOrgLimits/testGetStorageDetailWithoutPermissionThrowsAuraHandled
      Exception both green, Jest oiHealthStorage 3/3 green — all confirmed via actual `sf apex run
test`/Jest runs against entTrial, not assumed.
- [ ] Remediation Management workspace
- [ ] Navigation service extension (build on `OI_MetadataNavigationService`)

## Testing gate after each domain

Run focused Apex + Jest for the touched classes/LWCs before moving on. Full Apex + full Jest + lint +
`entTrial` deploy validation once at the end (or when a natural checkpoint is reached).

## Key facts discovered this pass (avoid re-deriving)

- `OI_Graph_Node__c.Label__c` = friendly Describe label (e.g. "Account Name"); `Secondary_Key__c` =
  real API name (e.g. "Account.Name", "Account"). Classification and any API-name logic must read
  `Secondary_Key__c`, never `Label__c`.
- `Parent_Key__c` on a Field node already equals its owning Object node's key (ADR-0018
  denormalization) — bulk custom-field-count-per-object needs only
  `SELECT Parent_Key__c, Secondary_Key__c FROM OI_Graph_Node__c WHERE Parent_Key__c IN :objectKeys
AND Node_Type__c = 'SalesforceMetadata.CustomField'`, no edge traversal required.
- `OI_MetadataNavigationService` already exists and already does real, verified-against-a-real-org
  Setup navigation for CustomObject/CustomField/ApexClass/ApexTrigger/PermissionSet/Flow, with
  honest fallbacks. This is the Central Navigation Service the directive asks for — extend it, do
  not rebuild it.
- `OI_GraphEngine.getNodeDetail(nodeKey)` returns `OI_VersionRecord{typeKey, secondaryKey, ...}` —
  the bridge from a Finding's `Component_Key__c` to `OI_MetadataNavigationService.resolve(typeKey,
secondaryKey)`.
- Severity bands (`OI_Health_Severity_Descriptor__mdt`): Critical 0–39.9, Warning 40–69.9, Good
  70–100 — i.e. **higher score = healthier**. A per-finding "badness" score must be inverted
  (`100 - badness`) before calling `OI_HealthSeverityService.resolveSeverityKey` so both scales
  reuse one config source without contradicting each other.
- Field History Tracking does not support Long Text Area fields — `Notes__c`,
  `Compensating_Control__c`, `False_Positive_Justification__c` cannot get native before/after
  history. `Status__c` (Picklist) and `Due_Date__c` (Date) can; Owner history is automatic. This is
  why lifecycle history is scoped to those three, not "everything."
- **entTrial hit a genuine org-side schema-propagation delay for brand-new custom fields on
  2026-09-01.** Two full `force-app` deploys reported success (0 component errors) including the 6
  new `OI_Org_Health_Finding__c` lifecycle fields; a standalone single-field redeploy of `Score__c`
  reported `created:false, changed:false, state:Unchanged` with a real CustomField Id
  (`00Nf600000j5fdNEAQ`); yet `sf sobject describe`, the REST describe endpoint, AND raw anonymous
  Apex (`Schema.SObjectType.OI_Org_Health_Finding__c.fields.getMap()`) all agreed the object had
  only 40 fields, none of the 6 new ones. Ruled out: wrong org (orgId/instanceUrl/username matched
  across every command), namespace prefixing (`Organization.NamespacePrefix` is null), and
  leftover/stale state from an earlier bad attempt — proved this last point by deploying a brand
  new, never-before-seen field (`OI_Diag_Probe__c`) which itself came back `created:true,
changed:true` from the deploy yet was ALSO immediately invisible to the same Apex schema check.
  This is a real, reproducible, org-wide propagation delay in this specific trial org pod, not a
  code or metadata defect — every field-meta.xml is independently valid. `OI_Diag_Probe__c` is a
  disposable diagnostic field; delete it (and its deploy) once schema visibility is confirmed
  working again, it carries no product meaning. If this recurs on this org, re-run the same
  4-command proof (full deploy → single-field deploy state → REST describe → anonymous Apex
  `fields.getMap()`) before assuming a code bug, and simply wait longer — do not "fix" working
  metadata in response to this symptom.
- **Apex string literals escape a single quote with `\'`, never SQL-style `''`.** A first deploy
  attempt of this pass's new/rewritten test classes failed with 8 component errors, all narrative
  assertion-message strings containing a possessive ("org's", "Salesforce's", "rule's") written as
  doubled quotes — a SQL habit, not valid Apex. Fixed in
  `OI_MetadataClassificationServiceTest.cls`, `OI_MetadataHealthServiceTest.cls`, and
  `OI_OrgHealthFindingRepositoryTest.cls`. Any future narrative string containing a possessive/
  contraction must use `\'`.

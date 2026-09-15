/**
 * Purpose: Org Health's Metadata Health section (ADR-0026 Phase 2, Tier 2 — live, bounded,
 *          unpersisted) — ProductSpecs.md's "object shape and connectivity" signal: high
 *          field-count objects, high-degree objects, and objects with no incoming references
 *          detected.
 * Responsibilities: Read a bounded set of current Object nodes via OI_GraphEngine, classify each
 *                    one authoritatively (OI_MetadataClassificationService, bulk EntityDefinition
 *                    — never a per-object query, never a naming-convention guess), count each
 *                    object's own CUSTOM field count (never Salesforce's own standard fields —
 *                    ADR-0027 correction) and incoming relationship degree, score each rule's
 *                    evidence through the shared OI_HealthScoringEngine (confidence/impact/
 *                    exposure-aware, not a bare threshold jump), and shape the result for the
 *                    breakdown table + heatmap primitives.
 * Dependencies: OI_GraphEngine, OI_MetadataClassificationService, OI_HealthScoringEngine,
 *               OI_HealthSeverityService, OI_Org_Health_Section_Config__mdt,
 *               OI_Org_Health_Metric_Config__mdt.
 * Limitations: "Degree" is incoming-only (see OI_EdgeSelector.countCurrentByTargetKeysGroupedByKey's
 *              own doc comment) — a deliberate v1 connectivity signal, not a full bidirectional
 *              graph degree; this signal applies to every object regardless of classification —
 *              Standard/Managed objects are never suppressed from relationship, automation,
 *              code, permission, or dependency analysis, only from being penalized for fields
 *              Salesforce itself (not this org) chose to ship (ProductSpecs.md: "never penalize
 *              standard Salesforce metadata simply because Salesforce ships it with many fields
 *              or relationships"). Bounded by a ceiling (Live_Row_Ceiling__c, falling back to a
 *              built-in default): an org with more objects than the ceiling gets a truncated,
 *              honestly-labeled scan rather than an unbounded synchronous one; the per-object
 *              field enumeration used for the custom-field count carries its own independent row
 *              ceiling (OI_NodeSelector.selectCurrentFieldNodesByParentKeys), reported via the
 *              same coverage note when it, rather than the object ceiling, is what truncated.
 */
public with sharing class OI_MetadataHealthService {
  @TestVisible
  private static final String OBJECT_TYPE_KEY = 'SalesforceMetadata.CustomObject';
  @TestVisible
  private static final String FIELD_TYPE_KEY = 'SalesforceMetadata.CustomField';
  @TestVisible
  private static final Set<String> RELATIONSHIP_EDGE_TYPE_KEYS = new Set<String>{
    'SalesforceMetadata.LOOKUP_TO',
    'SalesforceMetadata.MASTER_DETAIL_TO'
  };

  private static final String SECTION_KEY = 'MetadataHealth';
  private static final String METRIC_HIGH_FIELD_COUNT = 'HighFieldCount';
  private static final String METRIC_HIGH_DEGREE = 'HighDegree';
  private static final String METRIC_ORPHAN_RATE = 'OrphanRate';
  private static final String METRIC_DEPENDENCY_DENSITY = 'DependencyDensity';
  private static final Integer DEFAULT_CEILING = 500;
  private static final Integer BREAKDOWN_ROW_LIMIT = 8;
  private static final Integer HEATMAP_ROW_LIMIT = 5;
  private static final Integer FIELD_ROW_CEILING = 20000;
  /** A KPI drill-down shows every matching object, not the breakdown table's top-8 — this
   * ceiling exists only to bound one response's size, not to hide results the way the
   * breakdown table's cap does. Comfortably above the section's own DEFAULT_CEILING (500). */
  private static final Integer DRILLDOWN_ROW_LIMIT = 500;
  /** Weight given to a rule's own primary magnitude signal — high enough that a single fully-confirmed (saturated magnitude, full confidence, full impact) signal alone can reach Critical, per OI_HealthScoringEngine's contract; confidence/impact/exposure are the actual dampeners, not this constant. */
  private static final Decimal PRIMARY_SIGNAL_WEIGHT = 90;
  private static final Decimal NO_REFERENCES_SIGNAL_WEIGHT = 45;

  private final OI_GraphEngine graphEngine;
  private final OI_HealthSeverityService severityService;
  private final OI_MetadataClassificationService classificationService;
  private final OI_HealthScoringEngine scoringEngine;

  public OI_MetadataHealthService() {
    this(
      new OI_GraphEngine(),
      new OI_HealthSeverityService(),
      new OI_MetadataClassificationService(),
      new OI_HealthScoringEngine()
    );
  }

  public OI_MetadataHealthService(
    OI_GraphEngine graphEngine,
    OI_HealthSeverityService severityService,
    OI_MetadataClassificationService classificationService,
    OI_HealthScoringEngine scoringEngine
  ) {
    this.graphEngine = graphEngine;
    this.severityService = severityService;
    this.classificationService = classificationService;
    this.scoringEngine = scoringEngine;
  }

  public OI_MetadataHealthDTO getMetadataHealthDetail() {
    Thresholds thresholds = loadThresholds();
    List<ObjectSignal> signals = buildAllSignals(thresholds);

    OI_MetadataHealthDTO dto = new OI_MetadataHealthDTO();
    dto.computedAt = Datetime.now();
    populateScoreAndFormula(dto, signals, thresholds);
    populateCoverage(dto, signals.size(), loadCeiling());
    populateKpiTiles(dto, signals);
    populateBreakdownAndHeatmap(dto, signals, thresholds);
    return dto;
  }

  /**
   * The full object list behind one KPI tile (see OI_HealthKpiDrilldownDTO) — reuses the exact
   * same signals getMetadataHealthDetail computes, never a second, drifting computation, and is
   * never re-truncated to a top-N the way the breakdown table is.
   */
  public OI_HealthKpiDrilldownDTO getKpiDrilldown(String metricKey) {
    Thresholds thresholds = loadThresholds();
    List<ObjectSignal> signals = buildAllSignals(thresholds);

    List<ObjectSignal> matching = new List<ObjectSignal>();
    String title;
    if (metricKey == METRIC_HIGH_FIELD_COUNT) {
      title = 'High field-count objects';
      for (ObjectSignal signal : signals) {
        if (signal.fieldScore.severityKey != 'Good') {
          matching.add(signal);
        }
      }
      matching.sort(new ByAttentionRank());
    } else if (metricKey == METRIC_HIGH_DEGREE) {
      title = 'High-degree objects';
      for (ObjectSignal signal : signals) {
        if (signal.degreeScore.severityKey != 'Good') {
          matching.add(signal);
        }
      }
      matching.sort(new ByAttentionRank());
    } else if (metricKey == METRIC_ORPHAN_RATE) {
      title = 'Objects with no incoming references detected';
      for (ObjectSignal signal : signals) {
        if (signal.hasNoIncomingReferences) {
          matching.add(signal);
        }
      }
      matching.sort(new ByAttentionRank());
    } else {
      /** 'Dependency density' is an org-wide average, not a per-object flag, so there is
       * nothing to "match" — the honest drill-down is the same objects ranked by the
       * signal that feeds the average, not a claim that every listed object is a problem. */
      title = 'Objects ranked by relationship degree';
      matching.addAll(signals);
      matching.sort(new ByDegreeDescending());
    }

    Integer shown = Math.min(DRILLDOWN_ROW_LIMIT, matching.size());
    OI_HealthKpiDrilldownDTO dto = new OI_HealthKpiDrilldownDTO();
    dto.title = title;
    dto.metricColumnLabels = new List<String>{ 'Fields', 'Degree' };
    dto.coverageCaption = shown == matching.size()
      ? matching.size() + (matching.size() == 1 ? ' object' : ' objects')
      : 'Top ' + shown + ' of ' + matching.size();
    for (Integer i = 0; i < shown; i++) {
      dto.rows.add(buildBreakdownRow(matching[i], thresholds));
    }
    return dto;
  }

  /**
   * The unified-finding-model view of this section's live signals (ADR-0027) — one candidate
   * per rule breach per object, not one blob per object, so each rule has its own identity,
   * evidence narrative, and severity that survives independently across scans. Reuses the
   * exact same query/threshold/signal logic getMetadataHealthDetail already computes — this
   * is a second projection of the same evidence, never a second, drifting computation of it.
   */
  public List<OI_OrgHealthFindingCandidate> getFindingCandidates() {
    Thresholds thresholds = loadThresholds();
    List<ObjectSignal> signals = buildAllSignals(thresholds);

    List<OI_OrgHealthFindingCandidate> candidates = new List<OI_OrgHealthFindingCandidate>();
    for (ObjectSignal signal : signals) {
      if (signal.fieldScore.severityKey != 'Good') {
        candidates.add(buildHighFieldCountCandidate(signal, thresholds));
      }
      if (signal.degreeScore.severityKey != 'Good') {
        candidates.add(buildHighDegreeCandidate(signal, thresholds));
      }
      if (signal.hasNoIncomingReferences) {
        candidates.add(buildNoIncomingReferencesCandidate(signal));
      }
    }
    return candidates;
  }

  private List<ObjectSignal> buildAllSignals(Thresholds thresholds) {
    Integer ceiling = loadCeiling();
    List<OI_Graph_Node__c> objects = graphEngine.selectCurrentNodesByTypeBounded(
      OBJECT_TYPE_KEY,
      ceiling
    );
    Set<String> objectKeys = new Set<String>();
    for (OI_Graph_Node__c obj : objects) {
      objectKeys.add(obj.Node_Key__c);
    }

    Map<String, String> apiNameByObjectKey = graphEngine.selectCurrentSecondaryKeysByKeys(
      objectKeys
    );
    Set<String> apiNames = new Set<String>(apiNameByObjectKey.values());
    Map<String, String> classificationByApiName = classificationService.classifyByApiName(
      apiNames
    );

    Map<String, Integer> customFieldCountByObjectKey = countCustomFieldsByObjectKey(
      objectKeys
    );
    Map<String, Integer> degreeByKey = graphEngine.countCurrentEdgesByTargetKeysGroupedByKey(
      objectKeys,
      RELATIONSHIP_EDGE_TYPE_KEYS
    );

    return buildSignals(
      objects,
      apiNameByObjectKey,
      classificationByApiName,
      customFieldCountByObjectKey,
      degreeByKey,
      thresholds
    );
  }

  /**
   * Counts only fields whose API name ends in "__c" per owning object — a hard platform
   * invariant for every custom field regardless of which object it lives on (unlike an
   * OBJECT's own "__c" suffix, which is ambiguous between this org's own custom object and a
   * managed package's, a field's is not: Salesforce enforces it, no exceptions), so this needs
   * no EntityDefinition round trip. Reads Field nodes directly by Parent_Key__c rather than a
   * two-hop edge-then-node join (see OI_NodeSelector.selectCurrentFieldNodesByParentKeys doc).
   */
  private Map<String, Integer> countCustomFieldsByObjectKey(
    Set<String> objectKeys
  ) {
    Map<String, Integer> counts = new Map<String, Integer>();
    List<OI_Graph_Node__c> fieldNodes = graphEngine.selectCurrentFieldNodesByParentKeys(
      objectKeys,
      FIELD_TYPE_KEY,
      FIELD_ROW_CEILING
    );
    for (OI_Graph_Node__c fieldNode : fieldNodes) {
      if (!isCustomFieldApiName(fieldNode.Secondary_Key__c)) {
        continue;
      }
      String objectKey = fieldNode.Parent_Key__c;
      Integer current = counts.containsKey(objectKey)
        ? counts.get(objectKey)
        : 0;
      counts.put(objectKey, current + 1);
    }
    return counts;
  }

  /** Secondary_Key__c for a field node is "Object.Field" (qualified API name) — the segment after the last dot is the field's own API name, which Salesforce guarantees ends "__c" for every custom field, on any object. */
  @TestVisible
  private static Boolean isCustomFieldApiName(String qualifiedFieldName) {
    if (String.isBlank(qualifiedFieldName)) {
      return false;
    }
    String fieldApiName = qualifiedFieldName.contains('.')
      ? qualifiedFieldName.substringAfterLast('.')
      : qualifiedFieldName;
    return fieldApiName.endsWithIgnoreCase('__c');
  }

  private OI_OrgHealthFindingCandidate buildHighFieldCountCandidate(
    ObjectSignal signal,
    Thresholds thresholds
  ) {
    Boolean isManaged =
      signal.classification == OI_MetadataClassificationService.MANAGED;
    OI_OrgHealthFindingCandidate candidate = new OI_OrgHealthFindingCandidate();
    candidate.sectionKey = SECTION_KEY;
    candidate.ruleId = 'MetadataHealth.HighFieldCount';
    candidate.ruleVersion = 2;
    candidate.title =
      signal.label + ' has an unusually high custom field count';
    candidate.severityKey = signal.fieldScore.severityKey;
    candidate.score = signal.fieldScore.score;
    candidate.scoreExplanation = signal.fieldScore.explanation;
    candidate.scoreContributorsJson = JSON.serialize(
      signal.fieldScore.contributors
    );
    candidate.confidence = isManaged ? 'Medium' : 'Medium';
    candidate.componentKey = signal.nodeKey;
    candidate.componentType = signal.classificationDisplay;
    candidate.componentLabel = signal.label;
    candidate.isManaged = isManaged;
    candidate.evidence =
      signal.customFieldCount +
      ' custom field(s) detected on ' +
      signal.label +
      ' (configured threshold: ' +
      thresholds.highFieldCountThreshold.intValue() +
      '). ' +
      signal.fieldScore.explanation;
    candidate.measuredValue = signal.customFieldCount + ' custom fields';
    candidate.expectedValue =
      '< ' +
      thresholds.highFieldCountThreshold.intValue() +
      ' custom fields';
    candidate.explanation = 'A high custom field count increases the surface area an administrator or integration must understand before making a safe change, and raises the chance that duplicate, deprecated, or unused fields have accumulated unnoticed. Salesforce-provided standard fields are excluded from this count — only fields this org (or an installed package) added are measured.';
    candidate.orgRisk = isManaged
      ? 'This object belongs to a managed package, so these fields were added by the package vendor, not this org\'s admins — the count reflects the vendor\'s design, not local sprawl, which is why this finding\'s severity is dampened.'
      : 'This is a custom field count this org (or an installed package\'s own customizations to it) controls directly — a high count here more often reflects incremental, ad-hoc field creation over time.';
    candidate.potentialImpact = 'Harder onboarding for new admins/developers, slower page-layout and report configuration, higher risk that a future change misses a relevant field, and closer proximity to the org\'s per-object field limit.';
    candidate.remediation = isManaged
      ? 'Fields on a managed-package object cannot be removed by this org; if the field count itself is a concern, raise it with the package vendor. This org can still audit which of these fields are actually used on its own layouts/reports.'
      : 'Run a field-usage audit (layouts, reports, automation, integrations, formulas) and retire fields with no detected usage; consolidate near-duplicate fields where safe.';
    candidate.validationSteps =
      'Re-run the Metadata Health scan after cleanup and confirm ' +
      signal.label +
      '\'s custom field count has dropped below ' +
      thresholds.highFieldCountThreshold.intValue() +
      ', or that this finding no longer appears.';
    return candidate;
  }

  private OI_OrgHealthFindingCandidate buildHighDegreeCandidate(
    ObjectSignal signal,
    Thresholds thresholds
  ) {
    Boolean isManaged =
      signal.classification == OI_MetadataClassificationService.MANAGED;
    OI_OrgHealthFindingCandidate candidate = new OI_OrgHealthFindingCandidate();
    candidate.sectionKey = SECTION_KEY;
    candidate.ruleId = 'MetadataHealth.HighDegree';
    candidate.ruleVersion = 2;
    candidate.title =
      signal.label + ' has an unusually high number of incoming relationships';
    candidate.severityKey = signal.degreeScore.severityKey;
    candidate.score = signal.degreeScore.score;
    candidate.scoreExplanation = signal.degreeScore.explanation;
    candidate.scoreContributorsJson = JSON.serialize(
      signal.degreeScore.contributors
    );
    candidate.confidence = 'Medium';
    candidate.componentKey = signal.nodeKey;
    candidate.componentType = signal.classificationDisplay;
    candidate.componentLabel = signal.label;
    candidate.isManaged = isManaged;
    candidate.evidence =
      signal.degree +
      ' incoming lookup/master-detail relationship edges detected (configured threshold: ' +
      thresholds.highDegreeThreshold.intValue() +
      '). ' +
      signal.degreeScore.explanation;
    candidate.measuredValue = signal.degree + ' incoming relationships';
    candidate.expectedValue =
      '< ' +
      thresholds.highDegreeThreshold.intValue() +
      ' incoming relationships';
    candidate.explanation = 'High incoming connectivity means many other objects hold a lookup or master-detail relationship to this one — this object sits at the center of a wide dependency blast radius. This applies to Standard and Managed objects exactly as it does to unmanaged custom ones: relationships this org built pointing at any object are this org\'s own concern, regardless of who owns the target object\'s definition.';
    candidate.orgRisk =
      'A change to this object (deleting a field it exposes, tightening its sharing model, adding a validation rule) can ripple into every one of the ' +
      signal.degree +
      ' referencing relationships — the more of those are this org\'s own custom automation and reports, the larger the real blast radius.';
    candidate.potentialImpact = 'A seemingly local change to this object can break automation, reports, or integrations on any of its referencing objects; testing the full blast radius before changing it becomes proportionally harder as this count grows.';
    candidate.remediation = 'Before changing this object, use the Org Intelligence graph to review every referencing relationship and confirm the change is safe for all of them; consider whether any relationships are stale and could be removed to shrink the blast radius.';
    candidate.validationSteps =
      'Re-run the Metadata Health scan after any cleanup and confirm the incoming relationship count for ' +
      signal.label +
      ' has dropped, or that this finding no longer appears.';
    return candidate;
  }

  private OI_OrgHealthFindingCandidate buildNoIncomingReferencesCandidate(
    ObjectSignal signal
  ) {
    Boolean isManaged =
      signal.classification == OI_MetadataClassificationService.MANAGED;
    OI_OrgHealthFindingCandidate candidate = new OI_OrgHealthFindingCandidate();
    candidate.sectionKey = SECTION_KEY;
    candidate.ruleId = 'MetadataHealth.NoIncomingReferences';
    candidate.ruleVersion = 2;
    candidate.title = 'No incoming references detected for ' + signal.label;
    candidate.severityKey = signal.noRefsScore.severityKey;
    candidate.score = signal.noRefsScore.score;
    candidate.scoreExplanation = signal.noRefsScore.explanation;
    candidate.scoreContributorsJson = JSON.serialize(
      signal.noRefsScore.contributors
    );
    candidate.confidence = 'Low';
    candidate.componentKey = signal.nodeKey;
    candidate.componentType = signal.classificationDisplay;
    candidate.componentLabel = signal.label;
    candidate.isManaged = isManaged;
    candidate.evidence =
      '0 incoming lookup/master-detail relationship edges detected for ' +
      signal.label +
      ' within current scan coverage.';
    candidate.measuredValue = '0 incoming relationships';
    candidate.expectedValue = 'Not applicable — informational, for review only';
    candidate.explanation = 'This graph signal only sees relationship edges the metadata scanners currently discover; it cannot see layouts, automation, reports, Apex, or integrations that might still reference this object by a path outside this scan\'s coverage.';
    candidate.orgRisk = 'A candidate for review, not proof this object is unused — confirm through Object Manager\'s own usage tooling and a search across layouts/automation/reports/code before treating it as safe to remove.';
    candidate.potentialImpact = 'Low on its own; the real risk is acting on this single low-confidence signal alone and archiving or deleting something still in active use elsewhere.';
    candidate.remediation = 'Before archiving or deleting this object, check its layouts, reports, flows, Apex, and any integrations for references not visible to this scan.';
    candidate.validationSteps = 'If manual review confirms the object is genuinely still in use, mark this finding Risk Accepted or False Positive with a note explaining why, rather than leaving it Open indefinitely.';
    return candidate;
  }

  private void populateScoreAndFormula(
    OI_MetadataHealthDTO dto,
    List<ObjectSignal> signals,
    Thresholds thresholds
  ) {
    Integer total = signals.size();
    Integer highFieldCount = 0;
    Integer highDegreeCount = 0;
    Integer orphanCount = 0;
    for (ObjectSignal signal : signals) {
      if (signal.fieldScore.severityKey != 'Good') {
        highFieldCount++;
      }
      if (signal.degreeScore.severityKey != 'Good') {
        highDegreeCount++;
      }
      if (signal.hasNoIncomingReferences) {
        orphanCount++;
      }
    }

    Decimal score;
    if (total == 0) {
      score = null;
    } else {
      Decimal penalty =
        (Decimal.valueOf(highFieldCount) / total) *
        thresholds.highFieldCountWeight +
        (Decimal.valueOf(highDegreeCount) / total) *
        thresholds.highDegreeWeight +
        (Decimal.valueOf(orphanCount) / total) * thresholds.orphanRateWeight;
      score = (100 - penalty).setScale(0, System.RoundingMode.HALF_UP);
      score = score < 0 ? 0 : (score > 100 ? 100 : score);
    }
    dto.score = score;
    dto.severityKey = severityService.resolveSeverityKey(score);

    dto.formulaSummary = '100 minus a weighted penalty for each rule below that an object breaches.';
    dto.formulaComponents.add(
      new OI_HealthKeyValueDTO(
        'High custom field count — objects with ≥ ' +
          thresholds.highFieldCountThreshold.intValue() +
          ' custom fields',
        '(weight ' + thresholds.highFieldCountWeight.intValue() + '%)'
      )
    );
    dto.formulaComponents.add(
      new OI_HealthKeyValueDTO(
        'High degree — objects with ≥ ' +
          thresholds.highDegreeThreshold.intValue() +
          ' relationship edges',
        '(weight ' + thresholds.highDegreeWeight.intValue() + '%)'
      )
    );
    dto.formulaComponents.add(
      new OI_HealthKeyValueDTO(
        'No-incoming-reference rate — objects with 0 incoming relationship edges detected within current scan coverage (not proof the object is unused)',
        '(weight ' + thresholds.orphanRateWeight.intValue() + '%)'
      )
    );
  }

  private void populateCoverage(
    OI_MetadataHealthDTO dto,
    Integer scannedCount,
    Integer ceiling
  ) {
    Boolean truncated = scannedCount >= ceiling;
    dto.isCoverageComplete = !truncated;
    dto.coverageNote = truncated
      ? scannedCount +
        ' objects scanned (ceiling reached — results may be incomplete)'
      : scannedCount + ' / ' + scannedCount + ' objects scanned';
  }

  private void populateKpiTiles(
    OI_MetadataHealthDTO dto,
    List<ObjectSignal> signals
  ) {
    Integer highFieldCount = 0;
    Integer highDegreeCount = 0;
    Integer orphanCount = 0;
    Long degreeSum = 0;
    for (ObjectSignal signal : signals) {
      if (signal.fieldScore.severityKey != 'Good') {
        highFieldCount++;
      }
      if (signal.degreeScore.severityKey != 'Good') {
        highDegreeCount++;
      }
      if (signal.hasNoIncomingReferences) {
        orphanCount++;
      }
      degreeSum += signal.degree;
    }
    Decimal density = signals.isEmpty()
      ? 0
      : (Decimal.valueOf(degreeSum) / signals.size())
          .setScale(1, System.RoundingMode.HALF_UP);

    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO(
        'High field-count objects',
        String.valueOf(highFieldCount),
        METRIC_HIGH_FIELD_COUNT
      )
    );
    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO(
        'High-degree objects',
        String.valueOf(highDegreeCount),
        METRIC_HIGH_DEGREE
      )
    );
    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO(
        'No incoming references detected',
        String.valueOf(orphanCount),
        METRIC_ORPHAN_RATE
      )
    );
    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO(
        'Dependency density',
        String.valueOf(density),
        METRIC_DEPENDENCY_DENSITY
      )
    );
  }

  private void populateBreakdownAndHeatmap(
    OI_MetadataHealthDTO dto,
    List<ObjectSignal> signals,
    Thresholds thresholds
  ) {
    List<ObjectSignal> ranked = signals.clone();
    ranked.sort(new ByAttentionRank());

    dto.breakdownTitle = 'Objects needing attention';
    dto.metricColumnLabels = new List<String>{ 'Fields', 'Degree' };
    Integer breakdownCount = Math.min(BREAKDOWN_ROW_LIMIT, ranked.size());
    dto.breakdownCoverageCaption =
      'Top ' +
      breakdownCount +
      ' of ' +
      signals.size();
    for (Integer i = 0; i < breakdownCount; i++) {
      dto.breakdownRows.add(buildBreakdownRow(ranked[i], thresholds));
    }

    dto.heatmapColumnLabels = new List<String>{
      'Fields',
      'Degree',
      'No refs detected'
    };
    Integer heatmapCount = Math.min(HEATMAP_ROW_LIMIT, ranked.size());
    for (Integer i = 0; i < heatmapCount; i++) {
      ObjectSignal signal = ranked[i];
      OI_HealthHeatmapRowDTO row = new OI_HealthHeatmapRowDTO();
      row.rowLabel = signal.label;
      row.cells.add(
        new OI_HealthMetricValueDTO(
          'fields',
          String.valueOf(signal.customFieldCount),
          signal.fieldScore.severityKey
        )
      );
      row.cells.add(
        new OI_HealthMetricValueDTO(
          'degree',
          String.valueOf(signal.degree),
          signal.degreeScore.severityKey
        )
      );
      row.cells.add(
        new OI_HealthMetricValueDTO(
          'norefs',
          signal.hasNoIncomingReferences ? 'Y' : 'N',
          signal.hasNoIncomingReferences
            ? signal.noRefsScore.severityKey
            : 'Good'
        )
      );
      dto.heatmapRows.add(row);
    }
  }

  /** Shared by the breakdown table (top-8) and the KPI drill-down (every matching row) so the
   * two never disagree about how one object's row is shaped. */
  private OI_HealthBreakdownRowDTO buildBreakdownRow(
    ObjectSignal signal,
    Thresholds thresholds
  ) {
    OI_HealthBreakdownRowDTO row = new OI_HealthBreakdownRowDTO();
    row.key = signal.nodeKey;
    row.primaryLabel = signal.label;
    row.metricValues.add(
      new OI_HealthMetricValueDTO(
        'fields',
        String.valueOf(signal.customFieldCount)
      )
    );
    row.metricValues.add(
      new OI_HealthMetricValueDTO('degree', String.valueOf(signal.degree))
    );
    row.severityKey = signal.severityKey;
    row.severityLabel = signal.severityKey;
    row.explanation = buildExplanation(signal, thresholds);
    return row;
  }

  /**
   * The always-available "why" for one object — built purely by formatting the same
   * threshold/measured values buildAllSignals already computed, never a second scoring pass.
   * This is what a breakdown or KPI-drilldown row shows before any finding has been synced.
   */
  private String buildExplanation(ObjectSignal signal, Thresholds thresholds) {
    List<String> reasons = new List<String>();
    if (signal.fieldScore.severityKey != 'Good') {
      reasons.add(
        signal.customFieldCount +
          ' custom fields — at or above this org\'s threshold of ' +
          thresholds.highFieldCountThreshold.intValue() +
          '.'
      );
    }
    if (signal.degreeScore.severityKey != 'Good') {
      reasons.add(
        signal.degree +
          ' incoming relationship edges — at or above this org\'s threshold of ' +
          thresholds.highDegreeThreshold.intValue() +
          '.'
      );
    }
    if (signal.hasNoIncomingReferences) {
      reasons.add(
        'No incoming references detected within the current scan — nothing appears to point to this object yet (not proof it is unused).'
      );
    }
    if (reasons.isEmpty()) {
      return 'No thresholds breached — field count and connectivity are within this org\'s configured ranges.';
    }
    return String.join(reasons, ' ');
  }

  private List<ObjectSignal> buildSignals(
    List<OI_Graph_Node__c> objects,
    Map<String, String> apiNameByObjectKey,
    Map<String, String> classificationByApiName,
    Map<String, Integer> customFieldCountByObjectKey,
    Map<String, Integer> degreeByKey,
    Thresholds thresholds
  ) {
    List<ObjectSignal> signals = new List<ObjectSignal>();
    for (OI_Graph_Node__c obj : objects) {
      String apiName = apiNameByObjectKey.get(obj.Node_Key__c);
      String classification = String.isBlank(apiName)
        ? OI_MetadataClassificationService.UNKNOWN
        : classificationByApiName.get(apiName);
      Integer customFieldCount = valueOrZero(
        customFieldCountByObjectKey,
        obj.Node_Key__c
      );
      Integer degree = valueOrZero(degreeByKey, obj.Node_Key__c);
      signals.add(
        new ObjectSignal(
          obj.Node_Key__c,
          obj.Label__c,
          classification,
          customFieldCount,
          degree,
          thresholds,
          scoringEngine
        )
      );
    }
    return signals;
  }

  private Integer valueOrZero(Map<String, Integer> counts, String key) {
    Integer value = counts.get(key);
    return value == null ? 0 : value;
  }

  private Thresholds loadThresholds() {
    Map<String, Decimal> thresholdByMetric = new Map<String, Decimal>();
    Map<String, Decimal> weightByMetric = new Map<String, Decimal>();
    for (
      OI_Org_Health_Metric_Config__mdt row : OI_Org_Health_Metric_Config__mdt.getAll()
        .values()
    ) {
      if (row.Section_Key__c != SECTION_KEY || row.Is_Active__c != true) {
        continue;
      }
      thresholdByMetric.put(row.Metric_Key__c, row.Threshold_Value__c);
      weightByMetric.put(row.Metric_Key__c, row.Weight__c);
    }
    return new Thresholds(
      decimalOrDefault(thresholdByMetric.get(METRIC_HIGH_FIELD_COUNT), 60),
      decimalOrDefault(weightByMetric.get(METRIC_HIGH_FIELD_COUNT), 35),
      decimalOrDefault(thresholdByMetric.get(METRIC_HIGH_DEGREE), 25),
      decimalOrDefault(weightByMetric.get(METRIC_HIGH_DEGREE), 35),
      decimalOrDefault(weightByMetric.get(METRIC_ORPHAN_RATE), 30)
    );
  }

  private Decimal decimalOrDefault(Decimal value, Decimal fallback) {
    return value == null ? fallback : value;
  }

  private Integer loadCeiling() {
    OI_Org_Health_Section_Config__mdt config = OI_Org_Health_Section_Config__mdt.getInstance(
      SECTION_KEY
    );
    if (config != null && config.Live_Row_Ceiling__c != null) {
      return config.Live_Row_Ceiling__c.intValue();
    }
    return DEFAULT_CEILING;
  }

  /** Sorts worst-first: Critical objects before Warning before Good, then by combined size within a severity tier. */
  private class ByAttentionRank implements Comparator<ObjectSignal> {
    public Integer compare(ObjectSignal a, ObjectSignal b) {
      Integer rankA = severityRank(a.severityKey);
      Integer rankB = severityRank(b.severityKey);
      if (rankA != rankB) {
        return rankA - rankB;
      }
      return (b.customFieldCount + b.degree) - (a.customFieldCount + a.degree);
    }

    private Integer severityRank(String severityKey) {
      if (severityKey == 'Critical') {
        return 0;
      }
      if (severityKey == 'Warning') {
        return 1;
      }
      return 2;
    }
  }

  /** Used only for the 'Dependency density' drill-down, which ranks every object by the same
   * signal that feeds the org-wide average rather than filtering to a breached subset. */
  private class ByDegreeDescending implements Comparator<ObjectSignal> {
    public Integer compare(ObjectSignal a, ObjectSignal b) {
      return b.degree - a.degree;
    }
  }

  /** One Object node's computed connectivity signal — an internal working shape, never returned directly. */
  private class ObjectSignal {
    String nodeKey;
    String label;
    String classification;
    String classificationDisplay;
    Integer customFieldCount;
    Integer degree;
    Boolean hasNoIncomingReferences;
    OI_HealthScoreResult fieldScore;
    OI_HealthScoreResult degreeScore;
    OI_HealthScoreResult noRefsScore;
    String severityKey;

    ObjectSignal(
      String nodeKey,
      String label,
      String classification,
      Integer customFieldCount,
      Integer degree,
      Thresholds thresholds,
      OI_HealthScoringEngine scoringEngine
    ) {
      this.nodeKey = nodeKey;
      this.label = String.isBlank(label) ? nodeKey : label;
      this.classification = classification;
      this.classificationDisplay = OI_MetadataClassificationService.displayLabel(
        classification
      );
      this.customFieldCount = customFieldCount;
      this.degree = degree;
      this.hasNoIncomingReferences = degree == 0;

      Boolean isManaged =
        classification == OI_MetadataClassificationService.MANAGED;
      Boolean isUnknown =
        classification == OI_MetadataClassificationService.UNKNOWN;

      this.fieldScore = scoringEngine.score(
        new List<OI_HealthSignal>{
          fieldCountSignal(
            customFieldCount,
            degree,
            thresholds.highFieldCountThreshold,
            isManaged,
            isUnknown
          )
        }
      );
      this.degreeScore = scoringEngine.score(
        new List<OI_HealthSignal>{
          degreeSignal(
            degree,
            thresholds.highDegreeThreshold,
            isManaged,
            isUnknown
          )
        }
      );
      this.noRefsScore = scoringEngine.score(
        new List<OI_HealthSignal>{
          noReferencesSignal(this.hasNoIncomingReferences, isManaged)
        }
      );

      this.severityKey = worstOf(
        fieldScore.severityKey,
        degreeScore.severityKey,
        hasNoIncomingReferences ? noRefsScore.severityKey : 'Good'
      );
    }

    private OI_HealthSignal fieldCountSignal(
      Integer customFieldCount,
      Integer degree,
      Decimal threshold,
      Boolean isManaged,
      Boolean isUnknown
    ) {
      OI_HealthSignal signal = new OI_HealthSignal(
        'FieldCountMagnitude',
        'Custom field count',
        PRIMARY_SIGNAL_WEIGHT,
        threshold > 0 ? Decimal.valueOf(customFieldCount) / threshold : 0,
        customFieldCount +
          ' custom fields vs. threshold ' +
          threshold.intValue()
      );
      signal.confidence = (isUnknown ? 0.75 * 0.7 : 0.75);
      signal.impactMultiplier = isManaged ? 0.4 : (isUnknown ? 0.7 : 1.0);
      /** A small, capped correlation-aware boost when the same object is also independently high-degree — a complex object that is also heavily referenced is a somewhat larger concern than either fact alone, without double-counting HighDegree's own separate finding. */
      signal.exposureMultiplier = degree >= threshold ? 1.15 : 1.0;
      return signal;
    }

    private OI_HealthSignal degreeSignal(
      Integer degree,
      Decimal threshold,
      Boolean isManaged,
      Boolean isUnknown
    ) {
      OI_HealthSignal signal = new OI_HealthSignal(
        'DegreeMagnitude',
        'Incoming relationship degree',
        PRIMARY_SIGNAL_WEIGHT,
        threshold > 0 ? Decimal.valueOf(degree) / threshold : 0,
        degree + ' incoming relationships vs. threshold ' + threshold.intValue()
      );
      signal.confidence = (isUnknown ? 0.8 * 0.7 : 0.8);
      signal.impactMultiplier = isManaged ? 0.6 : (isUnknown ? 0.8 : 1.0);
      return signal;
    }

    private OI_HealthSignal noReferencesSignal(
      Boolean hasNoIncomingReferences,
      Boolean isManaged
    ) {
      OI_HealthSignal signal = new OI_HealthSignal(
        'NoIncomingReferences',
        'No incoming references detected',
        NO_REFERENCES_SIGNAL_WEIGHT,
        hasNoIncomingReferences ? 1.5 : 0,
        hasNoIncomingReferences
          ? 'Zero incoming relationship edges detected within current scan coverage'
          : 'Has incoming references'
      );
      signal.confidence = 1.0;
      /** Capped low regardless of classification — a single graph signal is never proof of dead code (see class doc); this is informational, never Critical, by construction of its own weight/impact rather than a hardcoded override. */
      signal.impactMultiplier = isManaged ? 0.5 : 0.7;
      return signal;
    }

    private String worstOf(String a, String b, String c) {
      if (a == 'Critical' || b == 'Critical' || c == 'Critical') {
        return 'Critical';
      }
      if (a == 'Warning' || b == 'Warning' || c == 'Warning') {
        return 'Warning';
      }
      return 'Good';
    }
  }

  private class Thresholds {
    Decimal highFieldCountThreshold;
    Decimal highFieldCountWeight;
    Decimal highDegreeThreshold;
    Decimal highDegreeWeight;
    Decimal orphanRateWeight;

    Thresholds(
      Decimal highFieldCountThreshold,
      Decimal highFieldCountWeight,
      Decimal highDegreeThreshold,
      Decimal highDegreeWeight,
      Decimal orphanRateWeight
    ) {
      this.highFieldCountThreshold = highFieldCountThreshold;
      this.highFieldCountWeight = highFieldCountWeight;
      this.highDegreeThreshold = highDegreeThreshold;
      this.highDegreeWeight = highDegreeWeight;
      this.orphanRateWeight = orphanRateWeight;
    }
  }
}

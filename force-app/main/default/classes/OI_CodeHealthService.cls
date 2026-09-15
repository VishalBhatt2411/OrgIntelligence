/**
 * Purpose: Org Health's Code Health section (ADR-0026 Phase 3, Tier 2 — live, bounded,
 *          unpersisted) — ProductSpecs.md's Apex facts: dependency fan-in/out, cycles, and
 *          stale API versions. Is_Scored__c = true for this section (unlike Automation
 *          Health) — the spec's own "Any score must expose formula" line for Code Health, so
 *          the score/formula shape mirrors Metadata Health exactly. Each row's own severity is
 *          a real multi-signal judgment (OI_HealthScoringEngine, ADR-0027 correction), not a
 *          bare threshold jump.
 * Responsibilities: Read a bounded set of Apex classes directly via OI_ApexClassSelector
 *                    (standard ApexClass — no graph read needed for identity, the same
 *                    justified exception OI_NodeConnectionsService already establishes,
 *                    ADR-0026 §0.6), derive each class's graph Node_Key__c deterministically
 *                    (mirroring OI_MutationGenerator's own hash formula) to look up REFERENCES
 *                    fan-out/fan-in and cycle participation through OI_GraphEngine, score each
 *                    rule's evidence through the shared OI_HealthScoringEngine, and shape the
 *                    result for the breakdown table + heatmap primitives. Also the
 *                    unified-finding-model (ADR-0027) source for this section —
 *                    getFindingCandidates() projects the exact same evidence into one candidate
 *                    per rule breach per class.
 * Dependencies: OI_ApexClassSelector, OI_GraphEngine, OI_HealthSeverityService,
 *               OI_HealthScoringEngine, OI_HashUtil, OI_Org_Health_Section_Config__mdt,
 *               OI_Org_Health_Metric_Config__mdt, OI_GraphCycleDetector.
 * Limitations: Test coverage (the spec's third named Code Health fact) is deliberately NOT
 *              included — ApexCodeCoverageAggregate/ApexOrgWideCoverage are Tooling-API-only
 *              objects (confirmed invalid types for inline Apex SOQL), so surfacing coverage
 *              requires the still-unbuilt OI_ToolingApiAdapter (Backlog MS-2) — the same
 *              adapter Impact Analysis's own coverageCaveat already names as a blocker
 *              elsewhere. A named follow-up, not a silent omission (see OI_ApexClassSelector's
 *              own doc comment). Bounded by a ceiling (Live_Row_Ceiling__c, falling back to a
 *              built-in default): an org with more classes than the ceiling gets a truncated,
 *              honestly-labeled scan rather than an unbounded synchronous one.
 */
public with sharing class OI_CodeHealthService {
  @TestVisible
  private static final String APEX_CLASS_TYPE_KEY = 'SalesforceMetadata.ApexClass';
  @TestVisible
  private static final String REFERENCES_EDGE_TYPE_KEY = 'SalesforceMetadata.REFERENCES';

  private static final String SECTION_KEY = 'CodeHealth';
  private static final String METRIC_HIGH_DEPENDENCY = 'HighDependency';
  private static final String METRIC_OLD_API_VERSION = 'OldApiVersion';
  private static final Integer DEFAULT_CEILING = 500;
  private static final Integer BREAKDOWN_ROW_LIMIT = 8;
  private static final Integer HEATMAP_ROW_LIMIT = 5;
  /** How many API versions behind the configured threshold this signal's own magnitude scale normalizes against — mirrors the old "critical margin" concept, now feeding a confidence/impact-aware engine signal instead of a hardcoded cutoff. */
  private static final Decimal API_VERSION_MARGIN = 5;
  /** Mirrors OI_MetadataHealthService's/OI_AutomationHealthService's identical constants. */
  private static final Decimal PRIMARY_SIGNAL_WEIGHT = 90;
  private static final Decimal CYCLE_SIGNAL_WEIGHT = 45;

  private final OI_GraphEngine graphEngine;
  private final OI_ApexClassSelector classSelector;
  private final OI_HealthSeverityService severityService;
  private final OI_HealthScoringEngine scoringEngine;

  public OI_CodeHealthService() {
    this(
      new OI_GraphEngine(),
      new OI_ApexClassSelector(),
      new OI_HealthSeverityService(),
      new OI_HealthScoringEngine()
    );
  }

  public OI_CodeHealthService(
    OI_GraphEngine graphEngine,
    OI_ApexClassSelector classSelector,
    OI_HealthSeverityService severityService,
    OI_HealthScoringEngine scoringEngine
  ) {
    this.graphEngine = graphEngine;
    this.classSelector = classSelector;
    this.severityService = severityService;
    this.scoringEngine = scoringEngine;
  }

  public OI_CodeHealthDTO getCodeHealthDetail() {
    Thresholds thresholds = loadThresholds();
    Integer ceiling = loadCeiling();
    List<ClassSignal> signals = buildAllSignals(thresholds, ceiling);

    OI_CodeHealthDTO dto = new OI_CodeHealthDTO();
    dto.computedAt = Datetime.now();
    populateScoreAndFormula(dto, signals, thresholds);
    populateCoverage(dto, signals.size(), ceiling);
    populateKpiTiles(dto, signals);
    populateBreakdownAndHeatmap(dto, signals);
    return dto;
  }

  /**
   * The unified-finding-model view of this section's live signals (ADR-0027) — one candidate
   * per rule breach per class, reusing the exact same query/threshold/signal logic
   * getCodeHealthDetail already computes.
   */
  public List<OI_OrgHealthFindingCandidate> getFindingCandidates() {
    Thresholds thresholds = loadThresholds();
    List<ClassSignal> signals = buildAllSignals(thresholds, loadCeiling());

    List<OI_OrgHealthFindingCandidate> candidates = new List<OI_OrgHealthFindingCandidate>();
    for (ClassSignal signal : signals) {
      if (signal.dependencyScore.severityKey != 'Good') {
        candidates.add(buildHighDependencyCandidate(signal, thresholds));
      }
      if (signal.apiVersionScore.severityKey != 'Good') {
        candidates.add(buildOldApiVersionCandidate(signal, thresholds));
      }
      if (signal.isInCycle) {
        candidates.add(buildDependencyCycleCandidate(signal));
      }
    }
    return candidates;
  }

  private List<ClassSignal> buildAllSignals(
    Thresholds thresholds,
    Integer ceiling
  ) {
    List<ApexClass> classes = classSelector.selectClassesBounded(ceiling);

    Map<String, String> nodeKeyByClassId = new Map<String, String>();
    Set<String> nodeKeys = new Set<String>();
    for (ApexClass apexClass : classes) {
      String nodeKey = deriveApexClassNodeKey(apexClass);
      nodeKeyByClassId.put(apexClass.Id, nodeKey);
      nodeKeys.add(nodeKey);
    }

    Map<String, Integer> fanOutByKey = graphEngine.countCurrentEdgesBySourceKeysGroupedByKey(
      nodeKeys,
      new Set<String>{ REFERENCES_EDGE_TYPE_KEY }
    );
    Map<String, Integer> fanInByKey = graphEngine.countCurrentEdgesByTargetKeysGroupedByKey(
      nodeKeys,
      new Set<String>{ REFERENCES_EDGE_TYPE_KEY }
    );
    Set<String> cyclicKeys = detectCyclicClassKeys(
      classes,
      nodeKeyByClassId,
      nodeKeys
    );

    return buildSignals(
      classes,
      nodeKeyByClassId,
      fanOutByKey,
      fanInByKey,
      cyclicKeys,
      thresholds
    );
  }

  private OI_OrgHealthFindingCandidate buildHighDependencyCandidate(
    ClassSignal signal,
    Thresholds thresholds
  ) {
    OI_OrgHealthFindingCandidate candidate = new OI_OrgHealthFindingCandidate();
    candidate.sectionKey = SECTION_KEY;
    candidate.ruleId = 'CodeHealth.HighDependency';
    candidate.ruleVersion = 1;
    candidate.title =
      signal.label + ' has an unusually high combined fan-in/fan-out';
    candidate.severityKey = signal.dependencyScore.severityKey;
    candidate.score = signal.dependencyScore.score;
    candidate.scoreExplanation = signal.dependencyScore.explanation;
    candidate.scoreContributorsJson = JSON.serialize(
      signal.dependencyScore.contributors
    );
    candidate.confidence = 'Medium';
    candidate.componentKey = signal.nodeKey;
    candidate.componentType = 'Apex Class';
    candidate.componentLabel = signal.label;
    candidate.isManaged = false;
    candidate.evidence =
      (signal.fanOut + signal.fanIn) +
      ' combined REFERENCES fan-in/fan-out edges detected (configured threshold: ' +
      thresholds.highDependencyThreshold.intValue() +
      '). ' +
      signal.dependencyScore.explanation;
    candidate.measuredValue =
      (signal.fanOut + signal.fanIn) + ' combined fan-in/fan-out';
    candidate.expectedValue =
      '< ' +
      thresholds.highDependencyThreshold.intValue() +
      ' combined fan-in/fan-out';
    candidate.explanation = 'A high combined fan-in/fan-out means this class both depends on and is depended on by many other classes, making it harder to predict the full effect of a change and more likely to be a single point of failure.';
    candidate.orgRisk =
      'A change to this class can ripple through every one of its ' +
      (signal.fanOut + signal.fanIn) +
      ' detected dependency edges.';
    candidate.potentialImpact = 'Harder impact analysis before a safe change, higher likelihood a change here breaks other classes, longer test runs when this class is touched.';
    candidate.remediation = 'Review this class\'s dependencies in the Org Intelligence graph; consider whether responsibilities can be split across smaller, more independently testable classes.';
    candidate.validationSteps =
      'Re-run the Code Health scan after refactoring and confirm the combined fan-in/fan-out for ' +
      signal.label +
      ' has dropped below ' +
      thresholds.highDependencyThreshold.intValue() +
      ', or that this finding no longer appears.';
    return candidate;
  }

  private OI_OrgHealthFindingCandidate buildOldApiVersionCandidate(
    ClassSignal signal,
    Thresholds thresholds
  ) {
    OI_OrgHealthFindingCandidate candidate = new OI_OrgHealthFindingCandidate();
    candidate.sectionKey = SECTION_KEY;
    candidate.ruleId = 'CodeHealth.OldApiVersion';
    candidate.ruleVersion = 1;
    candidate.title =
      signal.label + ' is saved against a stale Apex API version';
    candidate.severityKey = signal.apiVersionScore.severityKey;
    candidate.score = signal.apiVersionScore.score;
    candidate.scoreExplanation = signal.apiVersionScore.explanation;
    candidate.scoreContributorsJson = JSON.serialize(
      signal.apiVersionScore.contributors
    );
    candidate.confidence = 'Medium';
    candidate.componentKey = signal.nodeKey;
    candidate.componentType = 'Apex Class';
    candidate.componentLabel = signal.label;
    candidate.isManaged = false;
    candidate.evidence =
      signal.label +
      ' is saved at API version ' +
      signal.apiVersion +
      ' (configured threshold: ' +
      thresholds.oldApiVersionThreshold.intValue() +
      '). ' +
      signal.apiVersionScore.explanation;
    candidate.measuredValue = 'API version ' + signal.apiVersion;
    candidate.expectedValue =
      '>= API version ' + thresholds.oldApiVersionThreshold.intValue();
    candidate.explanation = 'A class saved against an old API version does not receive newer platform runtime behaviors and security defaults (e.g. sharing/CRUD enforcement improvements) introduced in later releases, and signals the class has not been touched in a long time.';
    candidate.orgRisk = 'This class may be relying on legacy runtime behavior that newer API versions have since changed the default for, and is a candidate for a closer review before its next modification.';
    candidate.potentialImpact = 'Missing newer default protections, and a larger, riskier jump if this class is ever forced to update (e.g. by a platform deprecation) all at once.';
    candidate.remediation = 'Open this class in Setup and re-save it (or bump its metadata API version explicitly) after confirming its behavior is unaffected by the intervening API version changes documented in Salesforce release notes.';
    candidate.validationSteps = 'Re-run the Code Health scan after re-saving this class and confirm its API version now meets the configured threshold, or that this finding no longer appears.';
    return candidate;
  }

  private OI_OrgHealthFindingCandidate buildDependencyCycleCandidate(
    ClassSignal signal
  ) {
    OI_OrgHealthFindingCandidate candidate = new OI_OrgHealthFindingCandidate();
    candidate.sectionKey = SECTION_KEY;
    candidate.ruleId = 'CodeHealth.DependencyCycle';
    candidate.ruleVersion = 1;
    candidate.title = signal.label + ' participates in a dependency cycle';
    candidate.severityKey = signal.cycleScore.severityKey;
    candidate.score = signal.cycleScore.score;
    candidate.scoreExplanation = signal.cycleScore.explanation;
    candidate.scoreContributorsJson = JSON.serialize(
      signal.cycleScore.contributors
    );
    candidate.confidence = 'Low';
    candidate.componentKey = signal.nodeKey;
    candidate.componentType = 'Apex Class';
    candidate.componentLabel = signal.label;
    candidate.isManaged = false;
    candidate.evidence =
      signal.label +
      ' was detected participating in a REFERENCES dependency cycle with at least one other class within current scan coverage.';
    candidate.measuredValue = 'In a dependency cycle';
    candidate.expectedValue = 'Not applicable — informational, for review only';
    candidate.explanation = 'This graph signal only sees REFERENCES edges the Apex scanner currently discovers between classes; it is a starting point for review, not a confirmed defect.';
    candidate.orgRisk = 'A dependency cycle between classes can make execution order hard to reason about and increases the risk of an unintended circular call chain.';
    candidate.potentialImpact = 'Low confidence on its own; the real risk is treating this as confirmed without manually tracing the actual call path.';
    candidate.remediation = 'Use the Org Intelligence graph to trace the actual call path between the classes in this cycle and confirm whether it is intentional or an unintended coupling to break apart.';
    candidate.validationSteps = 'If manual review confirms the cycle is intentional and safe, mark this finding Risk Accepted with a note explaining why, rather than leaving it Open indefinitely.';
    return candidate;
  }

  /** Mirrors OI_MutationGenerator.deriveNodeKey exactly — the same deterministic hash the scan pipeline used to create this class's node, so no extra graph round-trip is needed just to resolve identity. */
  private String deriveApexClassNodeKey(ApexClass apexClass) {
    return deriveNodeKey(apexClass.NamespacePrefix, apexClass.Name);
  }

  /** Exposed statically (rather than only via the ApexClass-shaped overload) so tests can derive a real, already-deployed class's node key without needing to construct an ApexClass row — see OI_CodeHealthServiceTest's documented ApexClass-cannot-be-seeded-via-DML constraint. */
  @TestVisible
  private static String deriveNodeKey(
    String namespacePrefix,
    String className
  ) {
    String namespace = String.isBlank(namespacePrefix) ? '' : namespacePrefix;
    String fullyQualifiedName = String.isBlank(namespacePrefix)
      ? className
      : namespacePrefix + '.' + className;
    String raw =
      APEX_CLASS_TYPE_KEY +
      '::' +
      namespace +
      '::' +
      fullyQualifiedName;
    return OI_HashUtil.hash(raw);
  }

  private Set<String> detectCyclicClassKeys(
    List<ApexClass> classes,
    Map<String, String> nodeKeyByClassId,
    Set<String> nodeKeys
  ) {
    List<OI_Graph_Edge__c> internalEdges = graphEngine.selectCurrentEdgesBetweenKeys(
      nodeKeys,
      new Set<String>{ REFERENCES_EDGE_TYPE_KEY }
    );

    List<OI_NodeSummary> nodeSummaries = new List<OI_NodeSummary>();
    for (ApexClass apexClass : classes) {
      nodeSummaries.add(
        new OI_NodeSummary(
          nodeKeyByClassId.get(apexClass.Id),
          null,
          apexClass.Name,
          null,
          'Active'
        )
      );
    }
    List<OI_EdgeSummary> edgeSummaries = new List<OI_EdgeSummary>();
    for (OI_Graph_Edge__c edge : internalEdges) {
      edgeSummaries.add(
        new OI_EdgeSummary(
          edge.Edge_Key__c,
          edge.Edge_Type__c,
          edge.Source_Node_Key__c,
          edge.Target_Node_Key__c
        )
      );
    }
    OI_GraphFragment fragment = new OI_GraphFragment(
      null,
      nodeSummaries,
      edgeSummaries,
      new List<String>(),
      false,
      null
    );
    return OI_GraphCycleDetector.detectCycleParticipants(fragment, true);
  }

  private void populateScoreAndFormula(
    OI_CodeHealthDTO dto,
    List<ClassSignal> signals,
    Thresholds thresholds
  ) {
    Integer total = signals.size();
    Integer highDependencyCount = 0;
    Integer oldApiVersionCount = 0;
    for (ClassSignal signal : signals) {
      if (signal.isHighDependency) {
        highDependencyCount++;
      }
      if (signal.isOldApiVersion) {
        oldApiVersionCount++;
      }
    }

    Decimal score;
    if (total == 0) {
      score = null;
    } else {
      Decimal penalty =
        (Decimal.valueOf(highDependencyCount) / total) *
        thresholds.highDependencyWeight +
        (Decimal.valueOf(oldApiVersionCount) / total) *
        thresholds.oldApiVersionWeight;
      score = (100 - penalty).setScale(0, System.RoundingMode.HALF_UP);
      score = score < 0 ? 0 : (score > 100 ? 100 : score);
    }
    dto.score = score;
    dto.severityKey = severityService.resolveSeverityKey(score);

    dto.formulaSummary = 'Score = 100 − weighted penalty per threshold breached. Thresholds are admin-configurable in Org Health Settings.';
    dto.formulaComponents.add(
      new OI_HealthKeyValueDTO(
        'High dependency — classes with ≥ ' +
          thresholds.highDependencyThreshold.intValue() +
          ' combined fan-in/out edges',
        '(weight ' + thresholds.highDependencyWeight.intValue() + '%)'
      )
    );
    dto.formulaComponents.add(
      new OI_HealthKeyValueDTO(
        'Old API version — classes below API version ' +
        thresholds.oldApiVersionThreshold.intValue(),
        '(weight ' + thresholds.oldApiVersionWeight.intValue() + '%)'
      )
    );
  }

  private void populateCoverage(
    OI_CodeHealthDTO dto,
    Integer scannedCount,
    Integer ceiling
  ) {
    Boolean truncated = scannedCount >= ceiling;
    dto.isCoverageComplete = !truncated;
    dto.coverageNote = truncated
      ? scannedCount +
        ' classes scanned (ceiling reached — results may be incomplete)'
      : scannedCount + ' / ' + scannedCount + ' classes scanned';
  }

  private void populateKpiTiles(
    OI_CodeHealthDTO dto,
    List<ClassSignal> signals
  ) {
    Integer highDependencyCount = 0;
    Integer oldApiVersionCount = 0;
    Integer cyclicCount = 0;
    for (ClassSignal signal : signals) {
      if (signal.isHighDependency) {
        highDependencyCount++;
      }
      if (signal.isOldApiVersion) {
        oldApiVersionCount++;
      }
      if (signal.isInCycle) {
        cyclicCount++;
      }
    }

    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO(
        'Apex classes scanned',
        String.valueOf(signals.size())
      )
    );
    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO(
        'High-dependency classes',
        String.valueOf(highDependencyCount)
      )
    );
    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO(
        'Stale API version classes',
        String.valueOf(oldApiVersionCount)
      )
    );
    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO(
        'Classes in dependency cycles',
        String.valueOf(cyclicCount)
      )
    );
  }

  private void populateBreakdownAndHeatmap(
    OI_CodeHealthDTO dto,
    List<ClassSignal> signals
  ) {
    List<ClassSignal> ranked = signals.clone();
    ranked.sort(new ByAttentionRank());

    dto.breakdownTitle = 'Classes needing attention';
    dto.metricColumnLabels = new List<String>{ 'Dependencies', 'API Ver' };
    Integer breakdownCount = Math.min(BREAKDOWN_ROW_LIMIT, ranked.size());
    dto.breakdownCoverageCaption =
      'Top ' +
      breakdownCount +
      ' of ' +
      signals.size();
    for (Integer i = 0; i < breakdownCount; i++) {
      ClassSignal signal = ranked[i];
      OI_HealthBreakdownRowDTO row = new OI_HealthBreakdownRowDTO();
      row.key = signal.nodeKey;
      row.primaryLabel = signal.label;
      row.metricValues.add(
        new OI_HealthMetricValueDTO(
          'dependency',
          String.valueOf(signal.fanOut + signal.fanIn)
        )
      );
      row.metricValues.add(
        new OI_HealthMetricValueDTO(
          'apiVersion',
          String.valueOf(signal.apiVersion)
        )
      );
      row.severityKey = signal.severityKey;
      row.severityLabel = signal.severityKey;
      dto.breakdownRows.add(row);
    }

    dto.heatmapColumnLabels = new List<String>{ 'Dependencies', 'API Ver' };
    Integer heatmapCount = Math.min(HEATMAP_ROW_LIMIT, ranked.size());
    for (Integer i = 0; i < heatmapCount; i++) {
      ClassSignal signal = ranked[i];
      OI_HealthHeatmapRowDTO row = new OI_HealthHeatmapRowDTO();
      row.rowLabel = signal.label;
      row.cells.add(
        new OI_HealthMetricValueDTO(
          'dependency',
          String.valueOf(signal.fanOut + signal.fanIn),
          signal.dependencyScore.severityKey
        )
      );
      row.cells.add(
        new OI_HealthMetricValueDTO(
          'apiVersion',
          String.valueOf(signal.apiVersion),
          signal.apiVersionScore.severityKey
        )
      );
      dto.heatmapRows.add(row);
    }
  }

  private List<ClassSignal> buildSignals(
    List<ApexClass> classes,
    Map<String, String> nodeKeyByClassId,
    Map<String, Integer> fanOutByKey,
    Map<String, Integer> fanInByKey,
    Set<String> cyclicKeys,
    Thresholds thresholds
  ) {
    List<ClassSignal> signals = new List<ClassSignal>();
    for (ApexClass apexClass : classes) {
      String nodeKey = nodeKeyByClassId.get(apexClass.Id);
      Integer fanOut = valueOrZero(fanOutByKey, nodeKey);
      Integer fanIn = valueOrZero(fanInByKey, nodeKey);
      String label = String.isBlank(apexClass.NamespacePrefix)
        ? apexClass.Name
        : apexClass.NamespacePrefix + '.' + apexClass.Name;
      signals.add(
        new ClassSignal(
          nodeKey,
          label,
          apexClass.ApiVersion,
          fanOut,
          fanIn,
          cyclicKeys.contains(nodeKey),
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
      decimalOrDefault(thresholdByMetric.get(METRIC_HIGH_DEPENDENCY), 20),
      decimalOrDefault(weightByMetric.get(METRIC_HIGH_DEPENDENCY), 55),
      decimalOrDefault(thresholdByMetric.get(METRIC_OLD_API_VERSION), 55),
      decimalOrDefault(weightByMetric.get(METRIC_OLD_API_VERSION), 45)
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

  /** Sorts worst-first: classes in a cycle first, then Critical before Warning before Good, then by combined dependency size within a tier. */
  private class ByAttentionRank implements Comparator<ClassSignal> {
    public Integer compare(ClassSignal a, ClassSignal b) {
      Integer cycleRankA = a.isInCycle ? 0 : 1;
      Integer cycleRankB = b.isInCycle ? 0 : 1;
      if (cycleRankA != cycleRankB) {
        return cycleRankA - cycleRankB;
      }
      Integer rankA = severityRank(a.severityKey);
      Integer rankB = severityRank(b.severityKey);
      if (rankA != rankB) {
        return rankA - rankB;
      }
      return (b.fanOut + b.fanIn) - (a.fanOut + a.fanIn);
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

  /** One Apex class's computed signal — an internal working shape, never returned directly. */
  private class ClassSignal {
    String nodeKey;
    String label;
    Decimal apiVersion;
    Integer fanOut;
    Integer fanIn;
    Boolean isInCycle;
    Boolean isHighDependency;
    Boolean isOldApiVersion;
    OI_HealthScoreResult dependencyScore;
    OI_HealthScoreResult apiVersionScore;
    OI_HealthScoreResult cycleScore;
    String severityKey;

    ClassSignal(
      String nodeKey,
      String label,
      Decimal apiVersion,
      Integer fanOut,
      Integer fanIn,
      Boolean isInCycle,
      Thresholds thresholds,
      OI_HealthScoringEngine scoringEngine
    ) {
      this.nodeKey = nodeKey;
      this.label = label;
      this.apiVersion = apiVersion;
      this.fanOut = fanOut;
      this.fanIn = fanIn;
      this.isInCycle = isInCycle;
      this.isHighDependency =
        (fanOut + fanIn) >= thresholds.highDependencyThreshold;
      this.isOldApiVersion =
        apiVersion != null &&
        apiVersion < thresholds.oldApiVersionThreshold;

      this.dependencyScore = scoringEngine.score(
        new List<OI_HealthSignal>{
          dependencySignal(fanOut, fanIn, thresholds.highDependencyThreshold)
        }
      );
      this.apiVersionScore = scoringEngine.score(
        new List<OI_HealthSignal>{
          apiVersionSignal(apiVersion, thresholds.oldApiVersionThreshold)
        }
      );
      this.cycleScore = scoringEngine.score(
        new List<OI_HealthSignal>{ cycleSignal(isInCycle) }
      );

      /**
       * Cycle membership alone is confidence/impact-dampened below Critical by the scoring
       * engine itself (see cycleSignal's own weight/confidence/impact), not by a hardcoded
       * override — mirrors Automation Health's identical reasoning: a flagged cycle from
       * whatever REFERENCES edges are currently discovered is evidence to review, not
       * corroborated proof of a high-impact failure, UNLESS this same class is
       * independently already a confirmed high-dependency or stale-API-version one, in
       * which case the real signals combining to Critical is correct, not double-counted.
       */
      this.severityKey = worstOf(
        dependencyScore.severityKey,
        apiVersionScore.severityKey,
        isInCycle ? cycleScore.severityKey : 'Good'
      );
    }

    private OI_HealthSignal dependencySignal(
      Integer fanOut,
      Integer fanIn,
      Decimal threshold
    ) {
      Integer combined = fanOut + fanIn;
      OI_HealthSignal signal = new OI_HealthSignal(
        'HighDependency',
        'Combined fan-in/fan-out',
        PRIMARY_SIGNAL_WEIGHT,
        threshold > 0 ? Decimal.valueOf(combined) / threshold : 0,
        combined +
          ' combined REFERENCES fan-in/fan-out edges vs. threshold ' +
          threshold.intValue()
      );
      signal.confidence = 0.8;
      return signal;
    }

    /** value/threshold is inverted (threshold/value) since this signal is "lower is worse" — a class well below the configured minimum API version saturates the signal just like an over-threshold count would for a "higher is worse" one. */
    private OI_HealthSignal apiVersionSignal(
      Decimal apiVersion,
      Decimal threshold
    ) {
      Decimal magnitude = 0;
      String note = 'API version not available.';
      if (apiVersion != null && threshold > 0) {
        Decimal versionsBehind = threshold - apiVersion;
        magnitude = versionsBehind > 0
          ? versionsBehind / API_VERSION_MARGIN
          : 0;
        note =
          'API version ' +
          apiVersion +
          ' vs. threshold ' +
          threshold.intValue() +
          ' (' +
          (versionsBehind > 0 ? versionsBehind.intValue() : 0) +
          ' versions behind).';
      }
      OI_HealthSignal signal = new OI_HealthSignal(
        'OldApiVersion',
        'Stale Apex API version',
        PRIMARY_SIGNAL_WEIGHT,
        magnitude,
        note
      );
      signal.confidence = 0.75;
      return signal;
    }

    /** Weighted well below PRIMARY_SIGNAL_WEIGHT so this signal's own maximum possible contribution (weight × full saturation × full confidence × its own capped impact) can never alone cross into Critical — see class doc. */
    private OI_HealthSignal cycleSignal(Boolean isInCycle) {
      OI_HealthSignal signal = new OI_HealthSignal(
        'DependencyCycle',
        'Dependency cycle membership',
        CYCLE_SIGNAL_WEIGHT,
        isInCycle ? 1.5 : 0,
        isInCycle
          ? 'Participates in a REFERENCES dependency cycle within current scan coverage'
          : 'Not in a detected cycle'
      );
      signal.confidence = 1.0;
      signal.impactMultiplier = 0.8;
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
    Decimal highDependencyThreshold;
    Decimal highDependencyWeight;
    Decimal oldApiVersionThreshold;
    Decimal oldApiVersionWeight;

    Thresholds(
      Decimal highDependencyThreshold,
      Decimal highDependencyWeight,
      Decimal oldApiVersionThreshold,
      Decimal oldApiVersionWeight
    ) {
      this.highDependencyThreshold = highDependencyThreshold;
      this.highDependencyWeight = highDependencyWeight;
      this.oldApiVersionThreshold = oldApiVersionThreshold;
      this.oldApiVersionWeight = oldApiVersionWeight;
    }
  }
}

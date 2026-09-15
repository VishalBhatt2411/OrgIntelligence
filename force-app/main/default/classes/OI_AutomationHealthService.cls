/**
 * Purpose: Org Health's Automation Health section (ADR-0026 Phase 3, Tier 2 — live, bounded,
 *          unpersisted) — ProductSpecs.md's automation facts: automation per Object, high
 *          fan-in/fan-out, cycles, high-impact components. Facts-only — Is_Scored__c = false
 *          (§0.3): the spec never asks this section for a top-level composite score, so none is
 *          computed or invented; each row's OWN severity, however, is a real multi-signal
 *          judgment (OI_HealthScoringEngine, ADR-0027 correction), not a bare threshold jump.
 * Responsibilities: Read a bounded set of current Trigger and Flow nodes via OI_GraphEngine,
 *                    aggregate their REFERENCES fan-out/fan-in (dependency degree) and
 *                    EXECUTES_ON target (the object each fires on), detect cycles among them
 *                    via OI_GraphCycleDetector, score each rule's evidence through the shared
 *                    OI_HealthScoringEngine, and shape the result for the breakdown table +
 *                    heatmap primitives. Also the unified-finding-model (ADR-0027) source for
 *                    this section — getFindingCandidates() projects the exact same evidence into
 *                    one candidate per rule breach per component.
 * Dependencies: OI_GraphEngine, OI_HealthScoringEngine, OI_Org_Health_Section_Config__mdt,
 *               OI_Org_Health_Metric_Config__mdt, OI_GraphCycleDetector.
 * Limitations: Fan-in on a Trigger/Flow is expected to be near-zero under current scanner
 *              coverage — nothing today records a REFERENCES edge pointing AT a trigger or
 *              flow (OI_DependencyEngineService's own documented coverage gap). Cycle
 *              detection is correspondingly limited to whatever REFERENCES edges the Apex
 *              scanners currently discover between automation components (e.g. a trigger
 *              handler class referencing another) — which is exactly why cycle membership alone
 *              is confidence-dampened below Critical in the scoring engine, not hard-capped by a
 *              special case. Bounded by a ceiling (Live_Row_Ceiling__c, falling back to a
 *              built-in default) applied per node type.
 */
public with sharing class OI_AutomationHealthService {
  @TestVisible
  private static final String APEX_TRIGGER_TYPE_KEY = 'SalesforceMetadata.ApexTrigger';
  @TestVisible
  private static final String FLOW_TYPE_KEY = 'SalesforceMetadata.Flow';
  @TestVisible
  private static final String EXECUTES_ON_EDGE_TYPE_KEY = 'SalesforceMetadata.EXECUTES_ON';
  @TestVisible
  private static final String REFERENCES_EDGE_TYPE_KEY = 'SalesforceMetadata.REFERENCES';

  private static final String SECTION_KEY = 'AutomationHealth';
  private static final String METRIC_HIGH_DEPENDENCY = 'HighDependency';
  private static final Integer DEFAULT_CEILING = 500;
  private static final Integer BREAKDOWN_ROW_LIMIT = 8;
  private static final Integer HEATMAP_ROW_LIMIT = 5;
  /** Mirrors OI_MetadataHealthService's identical constants — a single fully-confirmed, full-confidence, full-impact primary signal can alone reach Critical; the Cycle signal's own weight is deliberately lower (see cycleSignal doc) so cycle membership alone cannot. */
  private static final Decimal PRIMARY_SIGNAL_WEIGHT = 90;
  private static final Decimal CYCLE_SIGNAL_WEIGHT = 45;

  private final OI_GraphEngine graphEngine;
  private final OI_HealthScoringEngine scoringEngine;

  public OI_AutomationHealthService() {
    this(new OI_GraphEngine(), new OI_HealthScoringEngine());
  }

  public OI_AutomationHealthService(
    OI_GraphEngine graphEngine,
    OI_HealthScoringEngine scoringEngine
  ) {
    this.graphEngine = graphEngine;
    this.scoringEngine = scoringEngine;
  }

  public OI_AutomationHealthDTO getAutomationHealthDetail() {
    Decimal threshold = loadHighDependencyThreshold();
    Integer ceiling = loadCeiling();
    BuiltSignals built = buildAllSignals(threshold, ceiling);

    OI_AutomationHealthDTO dto = new OI_AutomationHealthDTO();
    dto.computedAt = Datetime.now();
    populateCoverage(dto, built.triggerCount, built.flowCount, ceiling);
    populateKpiTiles(
      dto,
      built.triggerCount,
      built.flowCount,
      built.signals,
      built.automationCountByObjectKey
    );
    populateBreakdownAndHeatmap(dto, built.signals);
    return dto;
  }

  /**
   * The unified-finding-model view of this section's live signals (ADR-0027) — one candidate
   * per rule breach per component, reusing the exact same query/threshold/signal logic
   * getAutomationHealthDetail already computes.
   */
  public List<OI_OrgHealthFindingCandidate> getFindingCandidates() {
    Decimal threshold = loadHighDependencyThreshold();
    BuiltSignals built = buildAllSignals(threshold, loadCeiling());

    List<OI_OrgHealthFindingCandidate> candidates = new List<OI_OrgHealthFindingCandidate>();
    for (ComponentSignal signal : built.signals) {
      if (signal.dependencyScore.severityKey != 'Good') {
        candidates.add(buildHighDependencyCandidate(signal, threshold));
      }
      if (signal.isInCycle) {
        candidates.add(buildDependencyCycleCandidate(signal));
      }
    }
    return candidates;
  }

  private BuiltSignals buildAllSignals(Decimal threshold, Integer ceiling) {
    List<OI_Graph_Node__c> triggers = graphEngine.selectCurrentNodesByTypeBounded(
      APEX_TRIGGER_TYPE_KEY,
      ceiling
    );
    List<OI_Graph_Node__c> flows = graphEngine.selectCurrentNodesByTypeBounded(
      FLOW_TYPE_KEY,
      ceiling
    );
    List<OI_Graph_Node__c> components = new List<OI_Graph_Node__c>();
    components.addAll(triggers);
    components.addAll(flows);

    /** selectCurrentNodesByTypeBounded's own SOQL does not project Node_Type__c (no caller has
     * ever needed it before), so component type is tracked here from which of the two typed
     * queries a key came from, rather than read back off the merged row (which would throw
     * SObjectException: field not queried). */
    Map<String, String> componentTypeByKey = new Map<String, String>();
    for (OI_Graph_Node__c triggerNode : triggers) {
      componentTypeByKey.put(triggerNode.Node_Key__c, 'Apex Trigger');
    }
    for (OI_Graph_Node__c flow : flows) {
      componentTypeByKey.put(flow.Node_Key__c, 'Flow');
    }

    Set<String> componentKeys = new Set<String>();
    for (OI_Graph_Node__c component : components) {
      componentKeys.add(component.Node_Key__c);
    }

    Map<String, Integer> fanOutByKey = graphEngine.countCurrentEdgesBySourceKeysGroupedByKey(
      componentKeys,
      new Set<String>{ REFERENCES_EDGE_TYPE_KEY }
    );
    Map<String, Integer> fanInByKey = graphEngine.countCurrentEdgesByTargetKeysGroupedByKey(
      componentKeys,
      new Set<String>{ REFERENCES_EDGE_TYPE_KEY }
    );
    Map<String, Integer> automationCountByObjectKey = graphEngine.countCurrentEdgesBySourceKeysGroupedByTargetKey(
      componentKeys,
      new Set<String>{ EXECUTES_ON_EDGE_TYPE_KEY }
    );
    Set<String> cyclicKeys = detectCyclicComponentKeys(
      components,
      componentKeys
    );

    List<ComponentSignal> signals = buildSignals(
      components,
      componentTypeByKey,
      fanOutByKey,
      fanInByKey,
      cyclicKeys,
      threshold
    );

    BuiltSignals result = new BuiltSignals();
    result.signals = signals;
    result.triggerCount = triggers.size();
    result.flowCount = flows.size();
    result.automationCountByObjectKey = automationCountByObjectKey;
    return result;
  }

  private OI_OrgHealthFindingCandidate buildHighDependencyCandidate(
    ComponentSignal signal,
    Decimal threshold
  ) {
    OI_OrgHealthFindingCandidate candidate = new OI_OrgHealthFindingCandidate();
    candidate.sectionKey = SECTION_KEY;
    candidate.ruleId = 'AutomationHealth.HighDependency';
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
    candidate.componentType = signal.componentType;
    candidate.componentLabel = signal.label;
    candidate.isManaged = false;
    candidate.evidence =
      (signal.fanOut + signal.fanIn) +
      ' combined fan-in/fan-out REFERENCES edges detected (fan-out ' +
      signal.fanOut +
      ', fan-in ' +
      signal.fanIn +
      '; configured threshold: ' +
      threshold.intValue() +
      '). ' +
      signal.dependencyScore.explanation;
    candidate.measuredValue =
      (signal.fanOut + signal.fanIn) + ' combined fan-in/fan-out';
    candidate.expectedValue =
      '< ' +
      threshold.intValue() +
      ' combined fan-in/fan-out';
    candidate.explanation = 'A high combined fan-in/fan-out means this automation component both depends on and is depended on by many other components, making it harder to predict the full effect of a change and more likely to be a single point of failure for the automation graph.';
    candidate.orgRisk =
      'A change to this component (a modified condition, a new bypass, a disabled version) can ripple through every one of its ' +
      (signal.fanOut + signal.fanIn) +
      ' detected dependency edges.';
    candidate.potentialImpact = 'Harder impact analysis before a safe change, higher likelihood a change here breaks automation elsewhere, and closer proximity to any org-level automation complexity limits.';
    candidate.remediation = 'Review this component\'s dependencies in the Org Intelligence graph; consider whether responsibilities can be split across smaller, more independently testable components.';
    candidate.validationSteps =
      'Re-run the Automation Health scan after refactoring and confirm the combined fan-in/fan-out for ' +
      signal.label +
      ' has dropped below ' +
      threshold.intValue() +
      ', or that this finding no longer appears.';
    return candidate;
  }

  private OI_OrgHealthFindingCandidate buildDependencyCycleCandidate(
    ComponentSignal signal
  ) {
    OI_OrgHealthFindingCandidate candidate = new OI_OrgHealthFindingCandidate();
    candidate.sectionKey = SECTION_KEY;
    candidate.ruleId = 'AutomationHealth.DependencyCycle';
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
    candidate.componentType = signal.componentType;
    candidate.componentLabel = signal.label;
    candidate.isManaged = false;
    candidate.evidence =
      signal.label +
      ' was detected participating in a REFERENCES dependency cycle with at least one other automation component within current scan coverage.';
    candidate.measuredValue = 'In a dependency cycle';
    candidate.expectedValue = 'Not applicable — informational, for review only';
    candidate.explanation = 'This graph signal only sees REFERENCES edges the Apex scanners currently discover between automation components; it cannot see every real runtime dependency (e.g. a Flow calling another Flow indirectly), so cycle detection here is a starting point for review, not a confirmed defect.';
    candidate.orgRisk = 'A dependency cycle can make execution order and recursion behavior hard to reason about, and can mask an unintended circular trigger/flow invocation.';
    candidate.potentialImpact = 'Low confidence on its own; the real risk is treating this as confirmed without manually tracing the actual execution path.';
    candidate.remediation = 'Use the Org Intelligence graph to trace the actual call/reference path between the components in this cycle and confirm whether it is intentional (e.g. a documented recursive pattern) or an unintended coupling to break apart.';
    candidate.validationSteps = 'If manual review confirms the cycle is intentional and safe, mark this finding Risk Accepted with a note explaining why, rather than leaving it Open indefinitely.';
    return candidate;
  }

  private Set<String> detectCyclicComponentKeys(
    List<OI_Graph_Node__c> components,
    Set<String> componentKeys
  ) {
    List<OI_Graph_Edge__c> internalEdges = graphEngine.selectCurrentEdgesBetweenKeys(
      componentKeys,
      new Set<String>{ REFERENCES_EDGE_TYPE_KEY }
    );

    List<OI_NodeSummary> nodeSummaries = new List<OI_NodeSummary>();
    for (OI_Graph_Node__c component : components) {
      nodeSummaries.add(
        new OI_NodeSummary(
          component.Node_Key__c,
          null,
          component.Label__c,
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

  private void populateCoverage(
    OI_AutomationHealthDTO dto,
    Integer triggerCount,
    Integer flowCount,
    Integer ceiling
  ) {
    Boolean truncated = triggerCount >= ceiling || flowCount >= ceiling;
    dto.isCoverageComplete = !truncated;
    Integer total = triggerCount + flowCount;
    dto.coverageNote = truncated
      ? total +
        ' automation components scanned (ceiling reached — results may be incomplete)'
      : total + ' / ' + total + ' automation components scanned';
  }

  private void populateKpiTiles(
    OI_AutomationHealthDTO dto,
    Integer triggerCount,
    Integer flowCount,
    List<ComponentSignal> signals,
    Map<String, Integer> automationCountByObjectKey
  ) {
    Integer highDependencyCount = 0;
    Integer cyclicCount = 0;
    for (ComponentSignal signal : signals) {
      if (signal.isHighDependency) {
        highDependencyCount++;
      }
      if (signal.isInCycle) {
        cyclicCount++;
      }
    }

    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO('Triggers scanned', String.valueOf(triggerCount))
    );
    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO('Flows scanned', String.valueOf(flowCount))
    );
    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO(
        'High fan-in/out components',
        String.valueOf(highDependencyCount)
      )
    );
    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO(
        'Components in dependency cycles',
        String.valueOf(cyclicCount)
      )
    );
    dto.kpiTiles.add(
      new OI_HealthKeyValueDTO(
        'Most automated object',
        resolveMostAutomatedObjectLabel(automationCountByObjectKey)
      )
    );
  }

  /** Resolves only the single top object's label (one bounded lookup) rather than loading labels for the whole map — this is the one fact that needs an object's name, not its key. */
  private String resolveMostAutomatedObjectLabel(
    Map<String, Integer> automationCountByObjectKey
  ) {
    String topObjectKey;
    Integer topCount = 0;
    for (String objectKey : automationCountByObjectKey.keySet()) {
      Integer count = automationCountByObjectKey.get(objectKey);
      if (count > topCount) {
        topCount = count;
        topObjectKey = objectKey;
      }
    }
    if (topObjectKey == null) {
      return 'None detected';
    }
    OI_VersionRecord objectRecord = graphEngine.getNodeDetail(topObjectKey);
    String label = objectRecord == null ? topObjectKey : objectRecord.label;
    return label + ' (' + topCount + ')';
  }

  private void populateBreakdownAndHeatmap(
    OI_AutomationHealthDTO dto,
    List<ComponentSignal> signals
  ) {
    List<ComponentSignal> ranked = signals.clone();
    ranked.sort(new ByAttentionRank());

    dto.breakdownTitle = 'Components needing attention';
    dto.metricColumnLabels = new List<String>{ 'Fan-out', 'Fan-in' };
    Integer breakdownCount = Math.min(BREAKDOWN_ROW_LIMIT, ranked.size());
    dto.breakdownCoverageCaption =
      'Top ' +
      breakdownCount +
      ' of ' +
      signals.size();
    for (Integer i = 0; i < breakdownCount; i++) {
      ComponentSignal signal = ranked[i];
      OI_HealthBreakdownRowDTO row = new OI_HealthBreakdownRowDTO();
      row.key = signal.nodeKey;
      row.primaryLabel = signal.label;
      row.metricValues.add(
        new OI_HealthMetricValueDTO('fanOut', String.valueOf(signal.fanOut))
      );
      row.metricValues.add(
        new OI_HealthMetricValueDTO('fanIn', String.valueOf(signal.fanIn))
      );
      row.severityKey = signal.severityKey;
      row.severityLabel = signal.severityKey;
      dto.breakdownRows.add(row);
    }

    dto.heatmapColumnLabels = new List<String>{ 'Fan-out', 'Fan-in', 'Cycle' };
    Integer heatmapCount = Math.min(HEATMAP_ROW_LIMIT, ranked.size());
    for (Integer i = 0; i < heatmapCount; i++) {
      ComponentSignal signal = ranked[i];
      OI_HealthHeatmapRowDTO row = new OI_HealthHeatmapRowDTO();
      row.rowLabel = signal.label;
      row.cells.add(
        new OI_HealthMetricValueDTO(
          'fanOut',
          String.valueOf(signal.fanOut),
          signal.dependencyScore.severityKey
        )
      );
      row.cells.add(
        new OI_HealthMetricValueDTO(
          'fanIn',
          String.valueOf(signal.fanIn),
          signal.dependencyScore.severityKey
        )
      );
      row.cells.add(
        new OI_HealthMetricValueDTO(
          'cycle',
          signal.isInCycle ? 'Y' : 'N',
          signal.isInCycle ? signal.cycleScore.severityKey : 'Good'
        )
      );
      dto.heatmapRows.add(row);
    }
  }

  private List<ComponentSignal> buildSignals(
    List<OI_Graph_Node__c> components,
    Map<String, String> componentTypeByKey,
    Map<String, Integer> fanOutByKey,
    Map<String, Integer> fanInByKey,
    Set<String> cyclicKeys,
    Decimal threshold
  ) {
    List<ComponentSignal> signals = new List<ComponentSignal>();
    for (OI_Graph_Node__c component : components) {
      Integer fanOut = valueOrZero(fanOutByKey, component.Node_Key__c);
      Integer fanIn = valueOrZero(fanInByKey, component.Node_Key__c);
      Boolean isInCycle = cyclicKeys.contains(component.Node_Key__c);
      String componentType = componentTypeByKey.get(component.Node_Key__c);
      signals.add(
        new ComponentSignal(
          component.Node_Key__c,
          component.Label__c,
          componentType,
          fanOut,
          fanIn,
          isInCycle,
          threshold,
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

  private Decimal loadHighDependencyThreshold() {
    for (
      OI_Org_Health_Metric_Config__mdt row : OI_Org_Health_Metric_Config__mdt.getAll()
        .values()
    ) {
      if (
        row.Section_Key__c == SECTION_KEY &&
        row.Metric_Key__c == METRIC_HIGH_DEPENDENCY &&
        row.Is_Active__c == true &&
        row.Threshold_Value__c != null
      ) {
        return row.Threshold_Value__c;
      }
    }
    return 10;
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

  /** Sorts worst-first: components in a cycle first, then Critical before Warning before Good, then by combined fan-in/out within a tier. */
  private class ByAttentionRank implements Comparator<ComponentSignal> {
    public Integer compare(ComponentSignal a, ComponentSignal b) {
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

  /** Working result of one buildAllSignals() pass — carries everything both getAutomationHealthDetail and getFindingCandidates need from the same evidence, so the two never drift apart into separate computations. */
  private class BuiltSignals {
    List<ComponentSignal> signals;
    Integer triggerCount;
    Integer flowCount;
    Map<String, Integer> automationCountByObjectKey;
  }

  /** One automation component's computed connectivity signal — an internal working shape, never returned directly. */
  private class ComponentSignal {
    String nodeKey;
    String label;
    String componentType;
    Integer fanOut;
    Integer fanIn;
    Boolean isInCycle;
    Boolean isHighDependency;
    OI_HealthScoreResult dependencyScore;
    OI_HealthScoreResult cycleScore;
    String severityKey;

    ComponentSignal(
      String nodeKey,
      String label,
      String componentType,
      Integer fanOut,
      Integer fanIn,
      Boolean isInCycle,
      Decimal threshold,
      OI_HealthScoringEngine scoringEngine
    ) {
      this.nodeKey = nodeKey;
      this.label = String.isBlank(label) ? nodeKey : label;
      this.componentType = componentType;
      this.fanOut = fanOut;
      this.fanIn = fanIn;
      this.isInCycle = isInCycle;
      this.isHighDependency = (fanOut + fanIn) >= threshold;

      this.dependencyScore = scoringEngine.score(
        new List<OI_HealthSignal>{ dependencySignal(fanOut, fanIn, threshold) }
      );
      this.cycleScore = scoringEngine.score(
        new List<OI_HealthSignal>{ cycleSignal(isInCycle) }
      );

      /**
       * Cycle membership alone is confidence-dampened below Critical by the scoring engine
       * itself (see cycleSignal's own weight/confidence), not by a hardcoded override — this
       * scanner's own documented coverage gap (fan-in on a Trigger/Flow is "expected to be
       * near-zero," cycle detection limited to whatever REFERENCES edges are currently
       * discovered) means one flagged cycle is evidence to review, not a confirmed
       * high-impact failure, UNLESS this same component is independently already a
       * confirmed high-dependency one — in which case both real signals combining to
       * Critical is the correct, not double-counted, outcome.
       */
      this.severityKey = worstOf(
        dependencyScore.severityKey,
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
          ' combined fan-in/fan-out vs. threshold ' +
          threshold.intValue()
      );
      signal.confidence = 0.8;
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

    private String worstOf(String a, String b) {
      if (a == 'Critical' || b == 'Critical') {
        return 'Critical';
      }
      if (a == 'Warning' || b == 'Warning') {
        return 'Warning';
      }
      return 'Good';
    }
  }
}
